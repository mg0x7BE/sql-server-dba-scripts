/*
    Performance / TempDB
    TempDB space, allocation contention, and file configuration checks.
*/

-- TempDB file layout, size, growth. Run first.
-- Want even-sized data files, fixed MB autogrowth (not percent), and a set max_size.
SELECT
    df.name AS file_name,
    df.type_desc,
    df.size / 128.0 AS size_mb,
    CASE df.max_size
        WHEN 0 THEN 'no autogrowth'
        WHEN -1 THEN 'unlimited'
        ELSE CAST(df.max_size / 128.0 AS varchar(20)) + ' MB'
    END AS max_size,
    CASE
        WHEN df.growth = 0 THEN 'fixed, will not grow'
        WHEN df.is_percent_growth = 1 THEN CAST(df.growth AS varchar(10)) + ' %'
        ELSE CAST(df.growth / 128.0 AS varchar(20)) + ' MB'
    END AS autogrowth,
    df.physical_name
FROM tempdb.sys.database_files AS df
ORDER BY df.type, df.file_id;

-- Live space usage per tempdb file (allocated vs used).
SELECT
    df.file_id,
    df.name AS file_name,
    df.type_desc,
    fsu.total_page_count / 128.0 AS total_mb,
    fsu.allocated_extent_page_count / 128.0 AS allocated_mb,
    fsu.unallocated_extent_page_count / 128.0 AS free_mb,
    fsu.user_object_reserved_page_count / 128.0 AS user_object_mb,
    fsu.internal_object_reserved_page_count / 128.0 AS internal_object_mb,
    fsu.version_store_reserved_page_count / 128.0 AS version_store_mb
FROM tempdb.sys.dm_db_file_space_usage AS fsu
JOIN tempdb.sys.database_files AS df
    ON df.file_id = fsu.file_id;

-- Volume free space for the tempdb files. Checks the disk can absorb autogrowth.
SELECT DISTINCT
    vs.volume_mount_point,
    vs.logical_volume_name,
    vs.total_bytes / 1024 / 1024 / 1024.0 AS volume_gb,
    vs.available_bytes / 1024 / 1024 / 1024.0 AS free_gb
FROM tempdb.sys.database_files AS df
CROSS APPLY sys.dm_os_volume_stats(DB_ID('tempdb'), df.file_id) AS vs;

-- Top 5 sessions by current tempdb allocation. Quick "who is using tempdb" check.
SELECT TOP (5)
    su.session_id,
    su.user_objects_alloc_page_count / 128.0 AS user_alloc_mb,
    su.internal_objects_alloc_page_count / 128.0 AS internal_alloc_mb,
    (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) / 128.0 AS total_alloc_mb
FROM tempdb.sys.dm_db_session_space_usage AS su
ORDER BY (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) DESC;

-- Per-session tempdb allocation with the session that owns it.
-- session_space_usage is cumulative for the connection; covers work done outside the current request.
SELECT
    su.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    su.user_objects_alloc_page_count / 128.0 AS user_alloc_mb,
    su.user_objects_dealloc_page_count / 128.0 AS user_dealloc_mb,
    su.internal_objects_alloc_page_count / 128.0 AS internal_alloc_mb,
    su.internal_objects_dealloc_page_count / 128.0 AS internal_dealloc_mb,
    s.cpu_time,
    s.memory_usage * 8 AS memory_kb,
    s.row_count
FROM tempdb.sys.dm_db_session_space_usage AS su
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = su.session_id
ORDER BY (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) DESC;

-- Active-request tempdb allocation joined to the running statement.
-- task_space_usage is per task (parallel queries have several), so aggregate per request first.
-- Covers in-flight work only; use it to catch a query mid-spill.
WITH task_alloc AS (
    SELECT
        tsu.session_id,
        tsu.request_id,
        SUM(tsu.user_objects_alloc_page_count) AS user_alloc_pages,
        SUM(tsu.internal_objects_alloc_page_count) AS internal_alloc_pages
    FROM tempdb.sys.dm_db_task_space_usage AS tsu
    GROUP BY tsu.session_id, tsu.request_id
    HAVING SUM(tsu.user_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) > 127  -- min 1 MB
)
SELECT
    ta.session_id,
    ta.request_id,
    s.login_name,
    s.host_name,
    s.program_name,
    ta.user_alloc_pages / 128.0 AS user_alloc_mb,
    ta.internal_alloc_pages / 128.0 AS internal_alloc_mb,
    st.text AS batch_text
FROM task_alloc AS ta
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = ta.session_id
LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = ta.session_id
    AND r.request_id = ta.request_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
ORDER BY (ta.user_alloc_pages + ta.internal_alloc_pages) DESC;

-- TempDB allocation-page contention: PFS/GAM/SGAM latch waits.
-- Rare on 2019+ (memory-optimized tempdb metadata); if seen, add data files or check workload.
SELECT
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    wt.blocking_session_id,
    wt.resource_description,
    CASE
        WHEN page_no = 1 OR page_no % 8088 = 0 THEN 'PFS'
        WHEN page_no = 2 OR (page_no - 2) % 511232 = 0 THEN 'GAM'
        WHEN page_no = 3 OR (page_no - 3) % 511232 = 0 THEN 'SGAM'
        ELSE 'other'
    END AS page_type
FROM sys.dm_os_waiting_tasks AS wt
CROSS APPLY (
    SELECT CAST(RIGHT(wt.resource_description, CHARINDEX(':', REVERSE(wt.resource_description)) - 1) AS bigint)
) AS p(page_no)
WHERE wt.wait_type LIKE 'PAGE%LATCH[_]%'
AND wt.resource_description LIKE '2:%';

-- Live requests waiting on a tempdb resource (wait_resource starts with '2:').
-- Shows the running statement and plan, plus who is blocking. Background/idle waits excluded.
SELECT
    r.session_id,
    r.wait_type,
    r.wait_resource,
    r.blocking_session_id,
    SUBSTRING(
        st.text,
        (r.statement_start_offset / 2) + 1,
        (CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE r.statement_end_offset
         END - r.statement_start_offset) / 2 + 1
    ) AS running_statement,
    qp.query_plan,
    r.total_elapsed_time AS elapsed_ms,
    r.cpu_time AS cpu_ms,
    r.reads,
    r.logical_reads,
    r.writes
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
WHERE r.wait_resource LIKE '2:%'
AND s.is_user_process = 1
AND r.wait_type IS NOT NULL
ORDER BY r.total_elapsed_time DESC;
