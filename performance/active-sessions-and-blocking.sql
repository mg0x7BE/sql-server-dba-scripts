/*
    Performance / Active sessions and blocking
    Live sessions, running requests, and blocking chains.
*/

-- For a richer all-in-one live activity view, see vendor/sp_whoisactive.sql.

-- Connection/session/request counts. Overall load at a glance.
SELECT 'connections' AS metric, COUNT(*) AS cnt FROM sys.dm_exec_connections
UNION ALL
SELECT 'sessions', COUNT(*) FROM sys.dm_exec_sessions
UNION ALL
SELECT 'requests', COUNT(*) FROM sys.dm_exec_requests
UNION ALL
SELECT 'user sessions', COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1;

-- Top 20 hosts by open session count. Finds connection hogs.
SELECT TOP (20) host_name, program_name, COUNT(*) AS session_count
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY host_name, program_name
ORDER BY session_count DESC, host_name;

-- Active user sessions (replaces sp_who2 'active').
SELECT s.session_id, s.login_name, s.host_name, s.program_name,
       s.status, s.cpu_time, s.reads, s.writes, s.memory_usage,
       s.last_request_start_time, s.last_request_end_time
FROM sys.dm_exec_sessions AS s
WHERE s.is_user_process = 1
ORDER BY s.cpu_time DESC;

-- User sessions that have done writes. Narrows down data changes / log growth.
SELECT session_id, login_name, host_name, program_name, reads, writes
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
  AND writes > 0
ORDER BY writes DESC;

-- Running requests now, with statement text and plan. Uncomment the ORDER BY you need.
SELECT r.session_id,
       r.blocking_session_id,
       r.status,
       r.command,
       DB_NAME(r.database_id) AS database_name,
       r.wait_type,
       r.wait_time,
       r.wait_resource,
       r.last_wait_type,
       r.total_elapsed_time,
       r.cpu_time,
       r.logical_reads,
       r.reads,
       r.writes,
       s.host_name,
       s.program_name,
       s.login_name,
       SUBSTRING(t.text,
                 r.statement_start_offset / 2 + 1,
                 (CASE WHEN r.statement_end_offset = -1
                       THEN DATALENGTH(t.text)
                       ELSE r.statement_end_offset
                  END - r.statement_start_offset) / 2 + 1) AS running_statement,
       t.text AS batch_text,
       p.query_plan
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
        ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS p
WHERE r.session_id <> @@SPID
  AND (r.wait_type IS NULL OR r.wait_type <> 'BROKER_RECEIVE_WAITFOR')
-- AND s.is_user_process = 1
-- AND r.database_id = DB_ID('YourDatabase')
ORDER BY r.total_elapsed_time DESC;     -- long running
-- ORDER BY r.logical_reads DESC;       -- high I/O
-- ORDER BY r.cpu_time DESC;            -- high CPU

-- Lock waits happening now. Confirm blocking is real before chasing chains.
SELECT session_id, blocking_session_id, wait_type, wait_duration_ms, resource_description
FROM sys.dm_os_waiting_tasks
WHERE wait_type LIKE N'LCK%'
ORDER BY wait_duration_ms DESC;

-- Blocked requests with the statement they are stuck on. Victims; pair with head-blocker query below.
SELECT r.session_id,
       r.blocking_session_id,
       r.status,
       r.command,
       r.wait_type,
       r.wait_time,
       t.text AS blocked_statement
FROM sys.dm_exec_requests AS r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;

-- Blocking chain with head blocker (recursive CTE). lead_blocker = root of each chain, chase that one.
WITH blocking AS (
    SELECT r.session_id,
           r.blocking_session_id,
           r.wait_type,
           r.wait_time,
           r.wait_resource
    FROM sys.dm_exec_requests AS r
    WHERE r.blocking_session_id <> 0
       OR EXISTS (SELECT 1 FROM sys.dm_exec_requests b
                  WHERE b.blocking_session_id = r.session_id)
),
chain AS (
    -- roots: blockers that are not themselves blocked
    SELECT b.session_id,
           b.blocking_session_id,
           b.wait_type,
           b.wait_time,
           b.wait_resource,
           0 AS lvl,
           b.session_id AS lead_blocker
    FROM blocking AS b
    WHERE b.blocking_session_id = 0
       OR NOT EXISTS (SELECT 1 FROM blocking p WHERE p.session_id = b.blocking_session_id)
    UNION ALL
    SELECT b.session_id,
           b.blocking_session_id,
           b.wait_type,
           b.wait_time,
           b.wait_resource,
           c.lvl + 1,
           c.lead_blocker
    FROM blocking AS b
    INNER JOIN chain AS c
            ON b.blocking_session_id = c.session_id
           AND b.session_id <> c.session_id
)
SELECT c.lead_blocker,
       c.lvl,
       c.session_id,
       c.blocking_session_id,
       c.wait_type,
       c.wait_time,
       c.wait_resource,
       s.login_name,
       s.host_name,
       s.program_name,
       t.text AS last_or_running_statement
FROM chain AS c
INNER JOIN sys.dm_exec_connections AS cn
        ON c.session_id = cn.session_id
OUTER APPLY sys.dm_exec_sql_text(cn.most_recent_sql_handle) AS t
LEFT JOIN sys.dm_exec_sessions AS s
        ON c.session_id = s.session_id
ORDER BY c.lead_blocker, c.lvl, c.session_id
OPTION (MAXRECURSION 1000);

-- Long-running open transactions. Stuck transactions hold locks and block log truncation.
SELECT st.session_id,
       at.transaction_id,
       at.name AS transaction_name,
       at.transaction_begin_time,
       DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) AS elapsed_sec,
       CASE at.transaction_type
            WHEN 1 THEN 'Read/write'
            WHEN 2 THEN 'Read-only'
            WHEN 3 THEN 'System'
            WHEN 4 THEN 'Distributed'
       END AS transaction_type,
       CASE at.transaction_state
            WHEN 0 THEN 'Not initialized'
            WHEN 1 THEN 'Initialized, not started'
            WHEN 2 THEN 'Active'
            WHEN 3 THEN 'Ended (read-only)'
            WHEN 4 THEN 'Commit initiated (distributed)'
            WHEN 5 THEN 'Prepared, awaiting resolution'
            WHEN 6 THEN 'Committed'
            WHEN 7 THEN 'Rolling back'
            WHEN 8 THEN 'Rolled back'
       END AS transaction_state,
       s.login_name,
       s.host_name,
       s.program_name
FROM sys.dm_tran_active_transactions AS at
INNER JOIN sys.dm_tran_session_transactions AS st
        ON at.transaction_id = st.transaction_id
LEFT JOIN sys.dm_exec_sessions AS s
        ON st.session_id = s.session_id
WHERE st.is_user_transaction = 1
ORDER BY at.transaction_begin_time;

-- Live-load perf counters: batch requests/sec, compilations/sec, lock waits/sec.
-- Per-second rates, so take two reads a few seconds apart and diff cntr_value.
-- Counter type 272696576 (PERF_COUNTER_BULK_COUNT) is cumulative, not a rate.
SELECT RTRIM(counter_name) AS counter_name,
       RTRIM(instance_name) AS instance_name,
       cntr_value
FROM sys.dm_os_performance_counters
WHERE (counter_name = 'Batch Requests/sec')
   OR (counter_name = 'SQL Compilations/sec')
   OR (counter_name = 'SQL Re-Compilations/sec')
   OR (counter_name = 'Processes blocked')
   OR (counter_name = 'Lock Waits/sec' AND instance_name = '_Total')
ORDER BY counter_name, instance_name;
