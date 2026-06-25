/*
    Performance / CPU
    CPU pressure: scheduler usage, signal vs resource waits, top CPU consumers.
*/

-- Scheduler health, one row per CPU scheduler.
-- runnable_tasks_count high and sustained = CPU pressure (tasks ready but waiting for a core).
-- pending_disk_io_count high points at IO, not CPU.
SELECT
    scheduler_id,
    cpu_id,
    is_online,
    current_tasks_count,
    runnable_tasks_count,
    current_workers_count,
    active_workers_count,
    work_queue_count,
    pending_disk_io_count
FROM sys.dm_os_schedulers
WHERE scheduler_id < 255
ORDER BY runnable_tasks_count DESC;

-- Signal vs resource wait ratio over a sampling window (snapshot-and-diff, no DBCC CLEAR).
-- High signal-wait pct = workers waiting for CPU after their resource arrives = CPU pressure.
-- Adjust the WAITFOR window for a longer/shorter sample.
IF OBJECT_ID('tempdb..#waits') IS NOT NULL DROP TABLE #waits;

SELECT wait_type, wait_time_ms, signal_wait_time_ms
INTO #waits
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
        'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK',
        'SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE',
        'CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
        'BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_MANUAL_EVENT','CLR_AUTO_EVENT',
        'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
        'XE_DISPATCHER_WAIT','XE_DISPATCHER_JOIN','SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        'HADR_FILESTREAM_IOMGR_IOCOMPLETION','DIRTY_PAGE_POLL','SP_SERVER_DIAGNOSTICS_SLEEP'
    );

WAITFOR DELAY '00:01:00';

SELECT
    CAST(100.0 * SUM(n.signal_wait_time_ms - o.signal_wait_time_ms)
        / NULLIF(SUM(n.wait_time_ms - o.wait_time_ms), 0) AS DECIMAL(5,2)) AS signal_wait_pct,
    CAST(100.0 * SUM((n.wait_time_ms - o.wait_time_ms) - (n.signal_wait_time_ms - o.signal_wait_time_ms))
        / NULLIF(SUM(n.wait_time_ms - o.wait_time_ms), 0) AS DECIMAL(5,2)) AS resource_wait_pct,
    SUM(n.wait_time_ms - o.wait_time_ms) AS delta_wait_ms
FROM sys.dm_os_wait_stats n
    JOIN #waits o ON o.wait_type = n.wait_type;

-- Recent instance CPU usage history from the scheduler monitor ring buffer.
-- One row per minute; SQL vs other-process vs idle. Use to spot whether SQL or something else burns the CPU.
-- Legacy: ring-buffer XML shredding, no supported DMV equivalent. Buffer holds ~256 minutes.
DECLARE @ts_now BIGINT = (SELECT ms_ticks FROM sys.dm_os_sys_info);

SELECT
    record_id,
    SQLProcessUtilization        AS sql_cpu_pct,
    100 - SystemIdle - SQLProcessUtilization AS other_process_cpu_pct,
    SystemIdle                   AS system_idle_pct,
    DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS event_time
FROM (
    SELECT
        record.value('(./Record/@id)[1]', 'int') AS record_id,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
        [timestamp]
    FROM (
        SELECT [timestamp], CONVERT(xml, record) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            AND record LIKE N'%<SystemHealth>%'
    ) AS x
) AS y
ORDER BY record_id DESC;

-- Per-database and per-procedure CPU attribution lives in query-store.sql (durable history).
-- For live-only triage, sys.dm_exec_requests / sys.dm_exec_query_stats are in active-sessions-and-blocking.sql.

-- To trace a specific thread back to a session, join sys.dm_os_schedulers / sys.dm_os_workers / sys.dm_os_tasks
-- to sys.dm_exec_requests on session_id (replaces the old Perfmon Thread-object KPID correlation).
