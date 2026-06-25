/*
    Performance / Wait statistics
    Historical top waits, live snapshot-and-diff sampling, THREADPOOL runbook.
*/

-- Ignorable idle/background waits, reused by the queries below.
IF OBJECT_ID('tempdb..#ignorable_waits') IS NOT NULL
    DROP TABLE #ignorable_waits;

CREATE TABLE #ignorable_waits (wait_type nvarchar(256) PRIMARY KEY);

INSERT #ignorable_waits (wait_type) VALUES
    ('REQUEST_FOR_DEADLOCK_SEARCH'),
    ('SQLTRACE_INCREMENTAL_FLUSH_SLEEP'),
    ('SQLTRACE_BUFFER_FLUSH'),
    ('SQLTRACE_WAIT_ENTRIES'),
    ('LAZYWRITER_SLEEP'),
    ('XE_TIMER_EVENT'),
    ('XE_DISPATCHER_WAIT'),
    ('XE_DISPATCHER_JOIN'),
    ('XE_LIVE_TARGET_TVF'),
    ('FT_IFTS_SCHEDULER_IDLE_WAIT'),
    ('FT_IFTSHC_MUTEX'),
    ('LOGMGR_QUEUE'),
    ('CHECKPOINT_QUEUE'),
    ('BROKER_TO_FLUSH'),
    ('BROKER_TASK_STOP'),
    ('BROKER_EVENTHANDLER'),
    ('BROKER_RECEIVE_WAITFOR'),
    ('BROKER_TRANSMITTER'),
    ('SLEEP_TASK'),
    ('SLEEP_SYSTEMTASK'),
    ('SLEEP_DBSTARTUP'),
    ('SLEEP_DCOMSTARTUP'),
    ('SLEEP_MASTERDBREADY'),
    ('SLEEP_MASTERMDREADY'),
    ('SLEEP_MASTERUPGRADED'),
    ('SLEEP_BPOOL_FLUSH'),
    ('SLEEP_BUFFERPOOL_HELPLW'),
    ('WAITFOR'),
    ('WAIT_FOR_RESULTS'),
    ('WAITFOR_TASKSHUTDOWN'),
    ('DBMIRROR_DBM_MUTEX'),
    ('DBMIRROR_DBM_EVENT'),
    ('DBMIRROR_EVENTS_QUEUE'),
    ('DBMIRROR_WORKER_QUEUE'),
    ('DBMIRRORING_CMD'),
    ('DISPATCHER_QUEUE_SEMAPHORE'),
    ('CLR_AUTO_EVENT'),
    ('CLR_MANUAL_EVENT'),
    ('CLR_SEMAPHORE'),
    ('DIRTY_PAGE_POLL'),
    ('ONDEMAND_TASK_QUEUE'),
    ('SP_SERVER_DIAGNOSTICS_SLEEP'),
    ('SOS_WORK_DISPATCHER'),
    ('PARALLEL_REDO_DRAIN_WORKER'),
    ('PARALLEL_REDO_LOG_CACHE'),
    ('PARALLEL_REDO_TRAN_LIST'),
    ('PARALLEL_REDO_WORKER_SYNC'),
    ('PARALLEL_REDO_WORKER_WAIT_WORK'),
    ('PWAIT_ALL_COMPONENTS_INITIALIZED'),
    ('PWAIT_DIRECTLOGCONSUMER_GETNEXT'),
    ('PREEMPTIVE_XE_GETTARGETSTATE'),
    ('PREEMPTIVE_OS_FLUSHFILEBUFFERS'),
    ('HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
    ('HADR_WORK_QUEUE'),
    ('HADR_TIMER_TASK'),
    ('HADR_CLUSAPI_CALL'),
    ('HADR_LOGCAPTURE_WAIT'),
    ('HADR_NOTIFICATION_DEQUEUE'),
    ('HADR_FILESTREAM_IOMGR'),
    ('HADR_FILESTREAM_PREPROC'),
    ('VDI_CLIENT_OTHER'),
    ('STARTUP_DEPENDENCY_MANAGER'),
    ('QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'),
    ('QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'),
    ('QDS_ASYNC_QUEUE'),
    ('QDS_SHUTDOWN_QUEUE'),
    ('SERVER_IDLE_CHECK'),
    ('WAIT_XTP_OFFLINE_CKPT_NEW_LOG'),
    ('WAIT_XTP_HOST_WAIT'),
    ('WAIT_XTP_CKPT_CLOSE'),
    ('WAIT_XTP_RECOVERY'),
    ('LOGMGR_PMM_LOG');

-- Add a wait you want to exclude before re-running:
-- INSERT #ignorable_waits (wait_type) VALUES ('');

-- Top cumulative waits since instance startup. Shows which subsystem dominates.
SELECT TOP 25
    os.wait_type,
    os.wait_time_ms,
    CAST(100. * os.wait_time_ms / SUM(os.wait_time_ms) OVER () AS NUMERIC(12,1)) AS pct_wait_time,
    os.waiting_tasks_count,
    CASE WHEN os.waiting_tasks_count > 0
        THEN CAST(os.wait_time_ms / (1. * os.waiting_tasks_count) AS NUMERIC(12,1))
        ELSE 0 END AS avg_wait_time_ms,
    CURRENT_TIMESTAMP AS sample_time
FROM sys.dm_os_wait_stats os
LEFT JOIN #ignorable_waits iw ON os.wait_type = iw.wait_type
WHERE iw.wait_type IS NULL
ORDER BY os.wait_time_ms DESC;
GO

-- Snapshot-and-diff sampling: live waits over an interval, no DBCC SQLPERF CLEAR.
-- Use when cumulative stats are dominated by old history. Needs #ignorable_waits above.
IF OBJECT_ID('tempdb..#wait_batches') IS NOT NULL
    DROP TABLE #wait_batches;
IF OBJECT_ID('tempdb..#wait_data') IS NOT NULL
    DROP TABLE #wait_data;

CREATE TABLE #wait_batches (
    batch_id int IDENTITY PRIMARY KEY,
    sample_time datetime NOT NULL
);
CREATE TABLE #wait_data (
    batch_id int NOT NULL,
    wait_type nvarchar(256) NOT NULL,
    wait_time_ms bigint NOT NULL,
    waiting_tasks bigint NOT NULL
);
CREATE CLUSTERED INDEX cx_wait_data ON #wait_data(batch_id);
GO

-- Temp proc: record @intervals samples @delay apart into #wait_data.
IF OBJECT_ID('tempdb..#get_wait_data') IS NOT NULL
    DROP PROCEDURE #get_wait_data;
GO
CREATE PROCEDURE #get_wait_data
    @intervals tinyint = 2,
    @delay char(12) = '00:00:30.000' /* 30 seconds */
AS
DECLARE @batch_id int,
    @current_interval tinyint,
    @msg nvarchar(max);

SET NOCOUNT ON;
SET @current_interval = 1;

WHILE @current_interval <= @intervals
BEGIN
    INSERT #wait_batches(sample_time)
    SELECT CURRENT_TIMESTAMP;

    SELECT @batch_id = SCOPE_IDENTITY();

    INSERT #wait_data (batch_id, wait_type, wait_time_ms, waiting_tasks)
    SELECT
        @batch_id,
        os.wait_type,
        os.wait_time_ms,
        os.waiting_tasks_count
    FROM sys.dm_os_wait_stats os
    LEFT JOIN #ignorable_waits iw ON os.wait_type = iw.wait_type
    WHERE iw.wait_type IS NULL;

    SET @msg = CONVERT(char(23), CURRENT_TIMESTAMP, 121) + N': Completed sample '
        + CAST(@current_interval AS nvarchar(4))
        + N' of ' + CAST(@intervals AS nvarchar(4)) + '.';
    RAISERROR (@msg, 0, 1) WITH NOWAIT;

    SET @current_interval = @current_interval + 1;

    IF @current_interval <= @intervals
        WAITFOR DELAY @delay;
END
GO

-- Take two samples 30 seconds apart.
EXEC #get_wait_data @intervals = 2, @delay = '00:00:30.000';
GO

-- Diff the latest two samples: waits accrued during the interval only.
WITH max_batch AS (
    SELECT TOP 1 batch_id, sample_time
    FROM #wait_batches
    ORDER BY batch_id DESC
)
SELECT
    b.sample_time AS second_sample_time,
    DATEDIFF(ss, wb1.sample_time, b.sample_time) AS sample_seconds,
    wd1.wait_type,
    CAST((wd2.wait_time_ms - wd1.wait_time_ms) / 1000. AS NUMERIC(12,1)) AS wait_time_sec,
    (wd2.waiting_tasks - wd1.waiting_tasks) AS waits,
    CASE WHEN (wd2.waiting_tasks - wd1.waiting_tasks) > 0
        THEN CAST((wd2.wait_time_ms - wd1.wait_time_ms)
            / (1.0 * (wd2.waiting_tasks - wd1.waiting_tasks)) AS NUMERIC(12,1))
        ELSE 0 END AS avg_ms_per_wait
FROM max_batch b
JOIN #wait_data wd2 ON wd2.batch_id = b.batch_id
JOIN #wait_data wd1 ON wd1.wait_type = wd2.wait_type AND wd2.batch_id - 1 = wd1.batch_id
JOIN #wait_batches wb1 ON wd1.batch_id = wb1.batch_id
WHERE (wd2.waiting_tasks - wd1.waiting_tasks) > 0
ORDER BY wait_time_sec DESC;
GO

-- THREADPOOL runbook: worker-thread exhaustion. Symptom is new connections hanging or timing out.
-- If you cannot log in, use the DAC: sqlcmd -A -S <server> (one reserved session).

-- Tasks parked waiting for a free worker. Many rows = worker starvation.
SELECT wt.session_id, wt.wait_duration_ms, wt.wait_type, wt.blocking_session_id, wt.resource_description
FROM sys.dm_os_waiting_tasks wt
WHERE wt.wait_type = 'THREADPOOL'
ORDER BY wt.wait_duration_ms DESC;
GO

-- Worker headroom: max configured vs currently allocated/active across schedulers.
-- max_workers_count near total_active = no threads left for new work.
SELECT
    (SELECT max_workers_count FROM sys.dm_os_sys_info) AS max_workers_count,
    SUM(active_workers_count) AS total_active_workers,
    SUM(current_workers_count) AS total_current_workers,
    SUM(runnable_tasks_count) AS total_runnable_tasks,
    SUM(work_queue_count) AS total_work_queue_count
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE';
GO

-- Live requests ordered by wait time to find the offender. Usual cause is
-- long-blocking chains or runaway parallel queries.
SELECT
    r.session_id,
    r.blocking_session_id,
    r.command,
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    r.cpu_time,
    r.logical_reads,
    DB_NAME(r.database_id) AS database_name,
    s.login_name,
    s.host_name,
    s.program_name
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
WHERE s.is_user_process = 1
ORDER BY r.wait_time DESC;
GO

-- Drill down on one offender: read the SQL it last sent. Set @SessionId from the query above.
-- Grabs the most recent handle (plus connection origin) and materializes the statement text.
DECLARE @SessionId int = 0; /* replace with the offending session_id */
SELECT
    c.session_id,
    c.connect_time,
    c.client_tcp_port,
    t.text AS most_recent_sql
FROM sys.dm_exec_connections c
OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
WHERE c.session_id = @SessionId;
GO

-- Replication agent sessions. Find the Distribution/Log Reader session, then capture its
-- waits with an XE wait_info session filtered on that session_id (see diagnostics/extended-events.sql).
-- Per-query wait attribution: sys.query_store_wait_stats.
SELECT session_id, program_name, login_name, reads, writes, logical_reads, DB_NAME(database_id) AS database_name
FROM sys.dm_exec_sessions
WHERE program_name LIKE 'Replication%'
ORDER BY session_id;
GO
