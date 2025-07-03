--##--##--##--##--##--##--##--##--## : CPU

/*

% Processor Time is the percentage of elapsed time that the processor spends to execute a non-Idle thread. It is
calculated by measuring the percentage of time that the processor spends executing the idle thread and then subtracting
that value from 100%. (Each processor has an idle thread that consumes cycles when no other threads are ready to run).
This counter is the primary indicator of processor activity, and displays the average percentage of busy time observed
during the sample interval. It should be noted that the accounting calculation of whether the processor is idle is
performed at an internal sampling interval of the system clock (10ms). On todays fast processors, % Processor Time can
therefore underestimate the processor utilization as the processor may be spending a lot of time servicing threads
between the system clock sampling interval. Workload based timer applications are one example  of applications  which
are more likely to be measured inaccurately as timers are signaled just after the sample is taken.

*/

-- Perfmon\Processor\% Processor Time

/*

Processor Queue Length is the number of threads in the processor queue. Unlike the disk counters, this counter counters,
this counter shows ready threads only, not threads that are running.  There is a single queue for processor time even on
computers with multiple processors. Therefore, if a computer has multiple processors, you need to divide this value by
the number of processors servicing the workload. A sustained processor queue of less than 10 threads per processor is
normally acceptable, dependent of the workload.

*/

-- Perfmon\System\Processor Queue Length

--##--##--##--##--##--##--##--##--## : RAM

-- Page life expectancy
SELECT
    object_name,
    counter_name,
    cntr_value as [PLE (seconds)]
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
  AND object_name LIKE '%Buffer Manager%';

-- Buffer cache hit ratio
SELECT
    (CAST(SUM(CASE WHEN counter_name = 'Buffer cache hit ratio' THEN cntr_value ELSE 0 END) AS FLOAT) /
     CAST(SUM(CASE WHEN counter_name = 'Buffer cache hit ratio base' THEN cntr_value ELSE 0 END) AS FLOAT)) * 100
    AS [Buffer Cache Hit Ratio %]
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Buffer Manager%'
  AND counter_name IN ('Buffer cache hit ratio', 'Buffer cache hit ratio base');

-- Memory Grants Pending
SELECT
    object_name,
    counter_name,
    cntr_value as [Memory Grants Pending]
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Memory Grants Pending'
  AND object_name LIKE '%Memory Manager%';

-- Physical Memory in use
SELECT physical_memory_in_use_kb /1024 AS physical_memory_in_use_MB,
       virtual_address_space_committed_kb /1024 AS virtual_address_space_committed_MB,
       virtual_address_space_available_kb /1024 AS virtual_address_space_available_MB,
       page_fault_count, process_physical_memory_low, process_virtual_memory_low
FROM sys.dm_os_process_memory

--##--##--##--##--##--##--##--##--## : Disk I/O

-- Azure Metrics

--##--##--##--##--##--##--##--##--## : Indexing

SELECT TOP 20
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    OBJECT_SCHEMA_NAME(mid.object_id) + '.' + OBJECT_NAME(mid.object_id) as [Table],
    'CREATE INDEX idx_' + CONVERT(varchar, mid.index_handle) + ' ON ' +
    OBJECT_SCHEMA_NAME(mid.object_id) + '.' + OBJECT_NAME(mid.object_id) + ' (' +
    ISNULL(mid.equality_columns, '') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END +
    ISNULL(mid.inequality_columns, '') + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_measure DESC;

--##--##--##--##--##--##--##--##--## : Wait Stats
                                                                                                       /*
=========================================================================================
 Skrypt do analizy kluczowych statystyk oczekiwań (Wait Stats) w SQL Server
 Wersja: 1.2 (Poprawiona)
 Autor: Gemini
-----------------------------------------------------------------------------------------
 Opis:
 Ten skrypt oblicza kluczowe wskaźniki wydajności na podstawie sys.dm_os_wait_stats:
    1. Procentowy udział czasu sygnału (Signal Wait Time %)
    2. Procentowy udział poszczególnych typów oczekiwań w całościowym czasie oczekiwania.

 Skrypt automatycznie ocenia każdy wskaźnik jako 'GOOD', 'WARNING' lub 'BAD'
 na podstawie zdefiniowanych progów.

 UWAGA: Statystyki są kumulowane od ostatniego restartu usługi SQL Server
 lub od ostatniego ręcznego wyczyszczenia statystyk.
=========================================================================================
*/

-- Czyszczenie statystyk (opcjonalne - odkomentuj, jeśli chcesz zacząć pomiar od nowa)
-- DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
-- GO


WITH [FilteredWaits] AS
    (
    -- Krok 1: Pobranie statystyk i odfiltrowanie "bezpiecznych" oczekiwań, które nie wskazują na problemy.
    SELECT
    wait_type,
    wait_time_ms,
    signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
    N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
    N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
    N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
    N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
    N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
    N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT',
    N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
    N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE', 'MEMORY_ALLOCATION_EXT',
    N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE',
    N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK',
    N'PREEMPTIVE_OS_FLUSHFILEBUFFERS', N'PREEMPTIVE_OS_AUTHENTICATIONOPS',
    N'PREEMPTIVE_OS_GENERICOPS', N'PREEMPTIVE_OS_LIBRARYOPS', N'PREEMPTIVE_OS_WAITFORSINGLEOBJECT',
    N'PREEMPTIVE_OS_WRITEFILE', N'PREEMPTIVE_XE_CALLBACKEXECUTE', N'PWAIT_ALL_COMPONENTS_INITIALIZED',
    N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
    N'QDS_ASYNC_QUEUE_SLEEP', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
    N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH',
    N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP',
    N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY',
    N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
    N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER',
    N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
    N'SQLTRACE_WAIT_ENTRIES', N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN',
    N'WAIT_XTP_RECOVERY', N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
    N'WAIT_XTP_CKPT_CLOSE', N'XE_BUFFERMGR_ALLPROCESSED_EVENT', N'XE_DISPATCHER_JOIN',
    N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
    )
    ),
    [Metrics] AS
    (
    -- Krok 2: Agregacja metryk, których szukamy, w jednym, spójnym zestawie.
    -- Obliczenie ogólnego Signal Wait Time %
    SELECT
    'Signal Wait Time' AS [MetricName],
    CAST(SUM(signal_wait_time_ms) * 100.0 / NULLIF(SUM(wait_time_ms), 0) AS DECIMAL(10, 2)) AS [PercentageValue]
    FROM [FilteredWaits]

    UNION ALL

    -- Obliczenie % dla poszczególnych typów oczekiwań
    SELECT
    -- Łączymy wszystkie typy PAGEIOLATCH w jedną grupę
    CASE WHEN wait_type LIKE 'PAGEIOLATCH_%' THEN 'PAGEIOLATCH' ELSE wait_type END AS [MetricName],
    CAST(SUM(wait_time_ms) * 100.0 / (SELECT NULLIF(SUM(wait_time_ms), 0) FROM [FilteredWaits]) AS DECIMAL(10, 2)) AS [PercentageValue]
    FROM [FilteredWaits]
    WHERE wait_type IN ('WRITELOG', 'RESOURCE_SEMAPHORE', 'SOS_SCHEDULER_YIELD', 'THREADPOOL')
    OR wait_type LIKE 'PAGEIOLATCH_%'
    GROUP BY CASE WHEN wait_type LIKE 'PAGEIOLATCH_%' THEN 'PAGEIOLATCH' ELSE wait_type END
    )
-- Krok 3: Wyświetlenie wyników wraz z oceną
SELECT
    m.MetricName AS [Metryka],
    m.PercentageValue AS [Wartość (%)],
    CASE
        WHEN m.MetricName = 'Signal Wait Time' THEN
            CASE
                WHEN m.PercentageValue > 30 THEN 'BAD'
                WHEN m.PercentageValue >= 15 THEN 'WARNING'
                ELSE 'GOOD'
END
WHEN m.MetricName = 'PAGEIOLATCH' THEN
            CASE
                WHEN m.PercentageValue > 25 THEN 'BAD'
                WHEN m.PercentageValue >= 10 THEN 'WARNING'
                ELSE 'GOOD'
END
WHEN m.MetricName = 'WRITELOG' THEN
             CASE
                WHEN m.PercentageValue > 25 THEN 'BAD'
                -- Przyjąłem, że zakres 10-25% dla WRITELOG to ostrzeżenie.
                WHEN m.PercentageValue >= 10 THEN 'WARNING'
                ELSE 'GOOD'
END
WHEN m.MetricName = 'RESOURCE_SEMAPHORE' THEN
            -- Uwaga: W podanych przez Ciebie kryteriach jest prawdopodobnie błąd.
            -- Zwykle <5% jest GOOD, a >5% jest BAD. Implementuję wg tej logiki.
            CASE
                WHEN m.PercentageValue > 5 THEN 'BAD'
                ELSE 'GOOD'
END
WHEN m.MetricName = 'SOS_SCHEDULER_YIELD' THEN
            CASE
                WHEN m.PercentageValue > 25 THEN 'BAD'
                WHEN m.PercentageValue >= 20 THEN 'WARNING'
                ELSE 'GOOD'
END
WHEN m.MetricName = 'THREADPOOL' THEN
            CASE
                WHEN m.PercentageValue > 0 THEN 'BAD'
                ELSE 'GOOD'
END
ELSE 'N/A'
END AS [Ocena],
    -- Dodajemy krótkie objaśnienie, co dana metryka oznacza
    CASE
        WHEN m.MetricName = 'Signal Wait Time' THEN 'Wysoka wartość wskazuje na presję na CPU (procesor nie nadąża z obsługą wątków).'
        WHEN m.MetricName = 'PAGEIOLATCH' THEN 'Wskazuje na problemy z podsystemem I/O (oczekiwanie na odczyt stron danych z dysku do pamięci).'
        WHEN m.MetricName = 'WRITELOG' THEN 'Wskazuje na problemy z podsystemem I/O (wydajność zapisu do pliku logu transakcyjnego).'
        WHEN m.MetricName = 'RESOURCE_SEMAPHORE' THEN 'Wskazuje na oczekiwanie na przydział pamięci dla zapytań. Może oznaczać niedobór RAM.'
        WHEN m.MetricName = 'SOS_SCHEDULER_YIELD' THEN 'Wskazuje na presję na CPU. Wątki dobrowolnie oddają procesor, bo wykonują długie operacje.'
        WHEN m.MetricName = 'THREADPOOL' THEN 'Wskazuje, że brakuje dostępnych wątków roboczych do obsługi zapytań. Poważny problem z obciążeniem.'
END AS [Prawdopodobna przyczyna]
FROM
    [Metrics] AS m -- POPRAWKA: Dodano brakujący alias 'AS m'
ORDER BY
    m.PercentageValue DESC;

--##--##--##--##--##--##--##--##--## : WAIT STATS ALTERNATIVE VERSION

-- SQL Server Wait Stats Health Check
-- This script checks key wait statistics and provides health assessment

-- Clean up temp tables if they exist
IF OBJECT_ID('tempdb..#wait_stats') IS NOT NULL DROP TABLE #wait_stats;
IF OBJECT_ID('tempdb..#total_stats') IS NOT NULL DROP TABLE #total_stats;
IF OBJECT_ID('tempdb..#wait_percentages') IS NOT NULL DROP TABLE #wait_percentages;

-- Collect wait stats excluding benign waits
SELECT
    wait_type,
    wait_time_ms,
    signal_wait_time_ms,
    waiting_tasks_count,
    wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
INTO #wait_stats
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    -- Exclude benign wait types
                        'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
                        'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
                        'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
                        'DBMIRROR_DBM_EVENT', 'DBMIRROR_DBM_MUTEX', 'DBMIRROR_EVENTS_QUEUE',
                        'DBMIRROR_WORKER_QUEUE', 'DBMIRRORING_CMD', 'DIRTY_PAGE_POLL',
                        'DISPATCHER_QUEUE_SEMAPHORE', 'EXECSYNC', 'FSAGENT',
                        'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX', 'HADR_CLUSAPI_CALL',
                        'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'HADR_LOGCAPTURE_WAIT',
                        'HADR_NOTIFICATION_DEQUEUE', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE',
                        'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
                        'MEMORY_ALLOCATION_EXT', 'ONDEMAND_TASK_QUEUE',
                        'PREEMPTIVE_XE_GETTARGETSTATE', 'PWAIT_ALL_COMPONENTS_INITIALIZED',
                        'PWAIT_DIRECTLOGCONSUMER_GETNEXT', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
                        'QDS_ASYNC_QUEUE', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
                        'QDS_SHUTDOWN_QUEUE', 'REDO_THREAD_PENDING_WORK', 'REQUEST_FOR_DEADLOCK_SEARCH',
                        'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP',
                        'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
                        'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK', 'SLEEP_TASK',
                        'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT', 'SP_SERVER_DIAGNOSTICS_SLEEP',
                        'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
                        'SQLTRACE_WAIT_ENTRIES', 'WAIT_FOR_RESULTS', 'WAITFOR',
                        'WAITFOR_TASKSHUTDOWN', 'WAIT_XTP_RECOVERY', 'WAIT_XTP_HOST_WAIT',
                        'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'WAIT_XTP_CKPT_CLOSE',
                        'XE_DISPATCHER_JOIN', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT'
    );

-- Calculate totals
SELECT
    SUM(wait_time_ms) AS total_wait_time_ms,
    SUM(signal_wait_time_ms) AS total_signal_wait_time_ms,
    SUM(resource_wait_time_ms) AS total_resource_wait_time_ms
INTO #total_stats
FROM #wait_stats;

-- Calculate percentages
SELECT
    w.wait_type,
    w.wait_time_ms,
    w.signal_wait_time_ms,
    w.waiting_tasks_count,
    CAST(100.0 * w.wait_time_ms / NULLIF(t.total_wait_time_ms, 0) AS DECIMAL(5,2)) AS wait_percentage
INTO #wait_percentages
FROM #wait_stats w
         CROSS JOIN #total_stats t;

-- Main health check results
PRINT '============================================';
PRINT 'SQL SERVER WAIT STATS HEALTH CHECK';
PRINT '============================================';
PRINT '';

-- Signal Wait Time Check
DECLARE @signal_pct DECIMAL(5,2);
SELECT @signal_pct = CAST(100.0 * total_signal_wait_time_ms / NULLIF(total_wait_time_ms, 0) AS DECIMAL(5,2))
FROM #total_stats;

SELECT
    'Signal Wait Time %' AS [Metric],
    CASE
        WHEN @signal_pct < 15 THEN 'GOOD'
        WHEN @signal_pct BETWEEN 15 AND 30 THEN 'WARNING'
        ELSE 'BAD'
END AS [Status],
    CAST(@signal_pct AS VARCHAR(10)) + '%' AS [Current Value],
    'Good: <15%, Warning: 15-30%, Bad: >30%' AS [Thresholds];

-- PAGEIOLATCH Check
DECLARE @pageio_pct DECIMAL(5,2);
SELECT @pageio_pct = ISNULL(SUM(wait_percentage), 0)
FROM #wait_percentages
WHERE wait_type LIKE 'PAGEIOLATCH%';

SELECT
    'PAGEIOLATCH %' AS [Metric],
    CASE
        WHEN @pageio_pct < 10 THEN 'GOOD'
        WHEN @pageio_pct BETWEEN 10 AND 25 THEN 'WARNING'
        ELSE 'BAD'
END AS [Status],
    CAST(@pageio_pct AS VARCHAR(10)) + '%' AS [Current Value],
    'Good: <10%, Warning: 10-25%, Bad: >25%' AS [Thresholds];

-- WRITELOG Check
DECLARE @writelog_pct DECIMAL(5,2);
SELECT @writelog_pct = ISNULL(SUM(wait_percentage), 0)
FROM #wait_percentages
WHERE wait_type = 'WRITELOG';

SELECT
    'WRITELOG %' AS [Metric],
    CASE
        WHEN @writelog_pct < 10 THEN 'GOOD'
        WHEN @writelog_pct BETWEEN 10 AND 25 THEN 'WARNING'
        ELSE 'BAD'
END AS [Status],
    CAST(@writelog_pct AS VARCHAR(10)) + '%' AS [Current Value],
    'Good: <10%, Warning: 10-25%, Bad: >25%' AS [Thresholds];

-- RESOURCE_SEMAPHORE Check
DECLARE @res_sem_pct DECIMAL(5,2);
SELECT @res_sem_pct = ISNULL(SUM(wait_percentage), 0)
FROM #wait_percentages
WHERE wait_type = 'RESOURCE_SEMAPHORE';

SELECT
    'RESOURCE_SEMAPHORE %' AS [Metric],
    CASE
        WHEN @res_sem_pct < 5 THEN 'GOOD'
        ELSE 'BAD'
END AS [Status],
    CAST(@res_sem_pct AS VARCHAR(10)) + '%' AS [Current Value],
    'Good: <5%, Bad: ≥5%' AS [Thresholds];

-- SOS_SCHEDULER_YIELD Check
DECLARE @sos_pct DECIMAL(5,2);
SELECT @sos_pct = ISNULL(SUM(wait_percentage), 0)
FROM #wait_percentages
WHERE wait_type = 'SOS_SCHEDULER_YIELD';

SELECT
    'SOS_SCHEDULER_YIELD %' AS [Metric],
    CASE
        WHEN @sos_pct < 20 THEN 'GOOD'
        WHEN @sos_pct BETWEEN 20 AND 25 THEN 'WARNING'
        ELSE 'BAD'
END AS [Status],
    CAST(@sos_pct AS VARCHAR(10)) + '%' AS [Current Value],
    'Good: <20%, Warning: 20-25%, Bad: >25%' AS [Thresholds];

-- THREADPOOL Check
DECLARE @threadpool_pct DECIMAL(5,2);
SELECT @threadpool_pct = ISNULL(SUM(wait_percentage), 0)
FROM #wait_percentages
WHERE wait_type = 'THREADPOOL';

SELECT
    'THREADPOOL %' AS [Metric],
    CASE
        WHEN @threadpool_pct = 0 THEN 'GOOD'
        ELSE 'BAD'
END AS [Status],
    CAST(@threadpool_pct AS VARCHAR(10)) + '%' AS [Current Value],
    'Good: 0%, Bad: >0%' AS [Thresholds];

-- Top 10 Wait Types
PRINT '';
PRINT '--- TOP 10 WAIT TYPES ---';
SELECT TOP 10
    wait_type AS [Wait Type],
    wait_percentage AS [Percentage],
    CAST(wait_time_ms / 1000.0 / 60.0 AS DECIMAL(10,2)) AS [Wait Time (min)],
    waiting_tasks_count AS [Task Count]
FROM #wait_percentages
ORDER BY wait_percentage DESC;

-- Problematic waits (over 5%)
PRINT '';
PRINT '--- WAITS OVER 5% ---';
SELECT
    wait_type AS [Wait Type],
    wait_percentage AS [Percentage],
    CAST(wait_time_ms / 1000.0 / 60.0 AS DECIMAL(10,2)) AS [Wait Time (min)],
    waiting_tasks_count AS [Task Count]
FROM #wait_percentages
WHERE wait_percentage > 5
ORDER BY wait_percentage DESC;

-- Summary statistics
PRINT '';
PRINT '--- SUMMARY ---';
SELECT
    'Total Wait Time' AS [Metric],
    CAST(total_wait_time_ms / 1000.0 / 60.0 AS DECIMAL(10,2)) AS [Minutes],
    CAST(total_wait_time_ms / 1000.0 / 60.0 / 60.0 AS DECIMAL(10,2)) AS [Hours]
FROM #total_stats
UNION ALL
SELECT
    'Total Signal Wait',
    CAST(total_signal_wait_time_ms / 1000.0 / 60.0 AS DECIMAL(10,2)),
    CAST(total_signal_wait_time_ms / 1000.0 / 60.0 / 60.0 AS DECIMAL(10,2))
FROM #total_stats
UNION ALL
SELECT
    'Total Resource Wait',
    CAST(total_resource_wait_time_ms / 1000.0 / 60.0 AS DECIMAL(10,2)),
    CAST(total_resource_wait_time_ms / 1000.0 / 60.0 / 60.0 AS DECIMAL(10,2))
FROM #total_stats;

-- Clean up
DROP TABLE #wait_stats;
DROP TABLE #total_stats;
DROP TABLE #wait_percentages;