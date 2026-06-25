/*
    Performance / Query Store
    Query Store: top resource queries, regressions, and forced plans.
*/

-- Confirm Query Store is ON and show its config.
-- desired_state vs actual_state mismatch means QS stopped (often read_only after hitting max size).
USE [YourDatabase];
GO
SELECT actual_state_desc,
       desired_state_desc,
       readonly_reason,
       current_storage_size_mb,
       max_storage_size_mb,
       flush_interval_seconds,
       interval_length_minutes,
       stale_query_threshold_days,
       query_capture_mode_desc,
       size_based_cleanup_mode_desc
FROM sys.database_query_store_options;

-- Top N queries by total/avg CPU over the recent window.
-- Durable history, unlike sys.dm_exec_query_stats which is live cache only.
USE [YourDatabase];
GO
DECLARE @TopN int = 25, @Hours int = 24;
SELECT TOP (@TopN)
       q.query_id,
       SUM(rs.count_executions)                                  AS executions,
       SUM(rs.avg_cpu_time * rs.count_executions) / 1000000.0    AS total_cpu_sec,
       AVG(rs.avg_cpu_time) / 1000.0                             AS avg_cpu_ms,
       AVG(rs.avg_duration) / 1000.0                             AS avg_duration_ms,
       MAX(rs.last_execution_time)                               AS last_execution_time,
       SUBSTRING(qt.query_sql_text, 1, 400)                      AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE rsi.start_time >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
GROUP BY q.query_id, SUBSTRING(qt.query_sql_text, 1, 400)
ORDER BY total_cpu_sec DESC;

-- Top N queries by average duration over the recent window.
-- Use for slow-response complaints rather than raw CPU.
USE [YourDatabase];
GO
DECLARE @TopN int = 25, @Hours int = 24;
SELECT TOP (@TopN)
       q.query_id,
       SUM(rs.count_executions)                AS executions,
       AVG(rs.avg_duration) / 1000.0           AS avg_duration_ms,
       MAX(rs.max_duration) / 1000.0           AS max_duration_ms,
       AVG(rs.avg_cpu_time) / 1000.0           AS avg_cpu_ms,
       MAX(rs.last_execution_time)             AS last_execution_time,
       SUBSTRING(qt.query_sql_text, 1, 400)    AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE rsi.start_time >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
GROUP BY q.query_id, SUBSTRING(qt.query_sql_text, 1, 400)
ORDER BY avg_duration_ms DESC;

-- Top N queries by total logical reads over the recent window.
-- Read-heavy queries are the usual missing-index / bad-plan suspects.
USE [YourDatabase];
GO
DECLARE @TopN int = 25, @Hours int = 24;
SELECT TOP (@TopN)
       q.query_id,
       SUM(rs.count_executions)                                          AS executions,
       SUM(rs.avg_logical_io_reads * rs.count_executions)                AS total_logical_reads,
       AVG(rs.avg_logical_io_reads)                                      AS avg_logical_reads,
       MAX(rs.last_execution_time)                                       AS last_execution_time,
       SUBSTRING(qt.query_sql_text, 1, 400)                              AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE rsi.start_time >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
GROUP BY q.query_id, SUBSTRING(qt.query_sql_text, 1, 400)
ORDER BY total_logical_reads DESC;

-- Top N queries by memory grant over the recent window.
-- Chase spills, RESOURCE_SEMAPHORE waits, and oversized grants.
USE [YourDatabase];
GO
DECLARE @TopN int = 25, @Hours int = 24;
SELECT TOP (@TopN)
       q.query_id,
       SUM(rs.count_executions)                                AS executions,
       AVG(rs.avg_query_max_used_memory) * 8 / 1024.0          AS avg_used_memory_mb,
       MAX(rs.max_query_max_used_memory) * 8 / 1024.0          AS max_used_memory_mb,
       MAX(rs.last_execution_time)                             AS last_execution_time,
       SUBSTRING(qt.query_sql_text, 1, 400)                    AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE rsi.start_time >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
GROUP BY q.query_id, SUBSTRING(qt.query_sql_text, 1, 400)
ORDER BY avg_used_memory_mb DESC;

-- Retrieve the plan(s) for one query_id, with text, containing object, and forced flag.
-- Feed it a query_id from the lists above. object_name is the proc/function that holds
-- the query (NULL for ad hoc). This is how you go from a query_id to the code to fix.
USE [YourDatabase];
GO
DECLARE @QueryId int = 0;  -- set to the query_id of interest
SELECT p.plan_id,
       p.query_id,
       OBJECT_SCHEMA_NAME(NULLIF(q.object_id, 0)) AS object_schema,
       OBJECT_NAME(NULLIF(q.object_id, 0))        AS object_name,
       p.is_forced_plan,
       p.last_execution_time,
       SUBSTRING(qt.query_sql_text, 1, 4000) AS query_text,
       TRY_CAST(p.query_plan AS xml)         AS query_plan
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE p.query_id = @QueryId;

-- Regressed queries: same query slower on a newer plan than on an older one.
-- Compares a recent window against an earlier baseline window; positive cpu_regression_ms means it got worse.
USE [YourDatabase];
GO
DECLARE @RecentHours int = 24, @BaselineHours int = 168, @MinExecutions int = 10;
WITH recent AS (
    SELECT p.query_id, p.plan_id,
           SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS avg_cpu_us,
           SUM(rs.count_executions) AS executions
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
    WHERE rsi.start_time >= DATEADD(HOUR, -@RecentHours, SYSUTCDATETIME())
    GROUP BY p.query_id, p.plan_id
),
baseline AS (
    SELECT p.query_id,
           SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS avg_cpu_us
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
    WHERE rsi.start_time >= DATEADD(HOUR, -@BaselineHours, SYSUTCDATETIME())
      AND rsi.start_time <  DATEADD(HOUR, -@RecentHours, SYSUTCDATETIME())
    GROUP BY p.query_id
)
SELECT r.query_id,
       r.plan_id                                          AS recent_plan_id,
       r.executions                                       AS recent_executions,
       b.avg_cpu_us / 1000.0                              AS baseline_avg_cpu_ms,
       r.avg_cpu_us / 1000.0                              AS recent_avg_cpu_ms,
       (r.avg_cpu_us - b.avg_cpu_us) / 1000.0             AS cpu_regression_ms,
       SUBSTRING(qt.query_sql_text, 1, 400)               AS query_text
FROM recent AS r
JOIN baseline AS b ON r.query_id = b.query_id
JOIN sys.query_store_query AS q ON r.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE r.executions >= @MinExecutions
  AND r.avg_cpu_us > b.avg_cpu_us * 1.5
ORDER BY cpu_regression_ms DESC;

-- List all currently forced plans.
-- last_force_failure_reason_desc <> 'NONE' means the forced plan is no longer being applied.
USE [YourDatabase];
GO
SELECT p.query_id,
       p.plan_id,
       p.force_failure_count,
       p.last_force_failure_reason_desc,
       p.last_execution_time,
       SUBSTRING(qt.query_sql_text, 1, 400) AS query_text
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE p.is_forced_plan = 1;

-- Force or unforce a plan. Intrusive: pins the optimizer to one plan.
-- Pick query_id + plan_id from the lists above, then uncomment the action you want.
USE [YourDatabase];
GO
DECLARE @QueryId int = 0, @PlanId int = 0;  -- set both before running
-- EXEC sys.sp_query_store_force_plan @query_id = @QueryId, @plan_id = @PlanId;
-- EXEC sys.sp_query_store_unforce_plan @query_id = @QueryId, @plan_id = @PlanId;
PRINT 'Set @QueryId/@PlanId and uncomment force or unforce above.';

-- Query Store hints applied to queries, both manual and auto-applied.
-- source <> 0 is system-generated: CE feedback, DOP feedback, memory grant feedback.
-- This is where automatic tuning inserts a hint that can reshape a plan and cause a regression.
-- Add WHERE qh.query_id = <id> to focus on one query. SQL Server 2022 and later.
USE [YourDatabase];
GO
SELECT qh.query_id,
       qh.source_desc,
       qh.query_hint_text,
       qh.query_hint_failure_count,
       qh.last_query_hint_failure_reason_desc,
       SUBSTRING(qt.query_sql_text, 1, 200) AS query_text
FROM sys.query_store_query_hints AS qh
JOIN sys.query_store_query AS q ON qh.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
ORDER BY qh.source DESC, qh.query_id;

-- Remove the Query Store hints for one query (clears manual and feedback hints).
-- Intrusive: the query goes back to optimizing without the hint. Set @QueryId, then uncomment.
USE [YourDatabase];
GO
DECLARE @QueryId int = 0;
-- EXEC sys.sp_query_store_clear_hints @query_id = @QueryId;
PRINT 'Set @QueryId and uncomment sp_query_store_clear_hints to remove its hints.';

-- Top wait categories from Query Store over the recent window.
-- Durable per-query wait history; pairs with sys.dm_os_wait_stats for the live picture.
USE [YourDatabase];
GO
DECLARE @Hours int = 24;
SELECT ws.wait_category_desc,
       SUM(ws.total_query_wait_time_ms)            AS total_wait_ms,
       SUM(ws.total_query_wait_time_ms)
           / NULLIF(SUM(rs.count_executions), 0)   AS avg_wait_ms_per_exec,
       SUM(rs.count_executions)                    AS executions
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_runtime_stats_interval AS rsi ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN sys.query_store_runtime_stats AS rs ON ws.plan_id = rs.plan_id
     AND ws.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
GROUP BY ws.wait_category_desc
ORDER BY total_wait_ms DESC;

-- DESTRUCTIVE: wipes all Query Store history for the database. Disabled by default.
-- Only run if QS is corrupt or you deliberately want a clean baseline.
-- ALTER DATABASE [YourDatabase] SET QUERY_STORE CLEAR;
