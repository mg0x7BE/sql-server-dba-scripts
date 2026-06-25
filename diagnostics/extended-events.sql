/*
    Diagnostics / Extended Events
    Extended Events sessions and reading targets; system_health.
*/

-- See docs/extended-events.md for terminology (events, targets, actions, predicates).

-- SQL Trace (sp_trace_*, fn_trace_*, sys.traces) is deprecated - use Extended Events instead.

-- List XE sessions and whether they are running.
-- running_sessions has no row when a defined session is stopped.
SELECT s.name,
       s.startup_state,
       CASE WHEN r.name IS NULL THEN 0 ELSE 1 END AS is_running
FROM sys.server_event_sessions s
LEFT JOIN sys.dm_xe_sessions r ON r.name = s.name
ORDER BY s.name;

-- Targets per running session and their file paths / buffer settings.
SELECT s.name AS session_name,
       t.target_name,
       t.execution_count,
       t.bytes_written,
       CAST(t.target_data AS XML) AS target_data
FROM sys.dm_xe_sessions s
JOIN sys.dm_xe_session_targets t ON t.event_session_address = s.address
ORDER BY s.name, t.target_name;

-- Read the always-on system_health session ring buffer.
-- First stop for errors, deadlocks, and long latch/lock waits before building a custom session.
SELECT CAST(t.target_data AS XML) AS ring_buffer
FROM sys.dm_xe_sessions s
JOIN sys.dm_xe_session_targets t ON t.event_session_address = s.address
WHERE s.name = N'system_health'
  AND t.target_name = N'ring_buffer';

-- Pull deadlock graphs from system_health (replaces trace flags 1204/1222).
WITH sh AS (
    SELECT CAST(t.target_data AS XML) AS target_data
    FROM sys.dm_xe_sessions s
    JOIN sys.dm_xe_session_targets t ON t.event_session_address = s.address
    WHERE s.name = N'system_health'
      AND t.target_name = N'ring_buffer'
)
SELECT n.value('(@timestamp)[1]', 'datetime2') AS event_time,
       n.query('.') AS deadlock_xml
FROM sh
CROSS APPLY sh.target_data.nodes('/RingBufferTarget/event[@name="xml_deadlock_report"]') AS q(n)
ORDER BY event_time DESC;
GO

-- Custom event_file session: capture waits, optionally filtered to one session.
-- Generalized from a replication-agent wait capture; set the filter to whatever spid you are chasing.
-- Adjust FILENAME to a path the SQL Server service account can write to.
DECLARE @SessionId int = 61;          -- spid to track; remove the WHERE clause to capture all
DECLARE @FilePath nvarchar(260) = N'C:\XEvents\WaitCapture.xel';

-- Recreate idiom: drops any existing WaitCapture definition (and stops it if running) before creating.
-- Destructive only to a session of this exact name; comment out if you must preserve an existing one.
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'WaitCapture')
    DROP EVENT SESSION WaitCapture ON SERVER;

DECLARE @sql nvarchar(max) = N'
CREATE EVENT SESSION WaitCapture ON SERVER
ADD EVENT sqlos.wait_info (
    ACTION (sqlserver.session_id, sqlserver.client_app_name)
    WHERE [sqlserver].[session_id] = ' + CAST(@SessionId AS nvarchar(10)) + N'
)
ADD TARGET package0.event_file (SET FILENAME = N''' + @FilePath + N''')
WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS);';
EXEC sys.sp_executesql @sql;
GO

-- Start capture.
ALTER EVENT SESSION WaitCapture ON SERVER STATE = START;
GO

-- Stop capture (definition and .xel file remain for reading).
ALTER EVENT SESSION WaitCapture ON SERVER STATE = STOP;
GO

-- Read the .xel target into a staging table.
-- New batch: redeclare the path. The trailing * matches the rollover suffix in the file name.
-- Single .xel; no separate .xem metadata file (legacy SQL Trace artifact).
DECLARE @ReadPath nvarchar(260) = N'C:\XEvents\WaitCapture*.xel';

IF OBJECT_ID('tempdb..#xe_raw') IS NOT NULL DROP TABLE #xe_raw;

SELECT CAST(event_data AS XML) AS event_data
INTO #xe_raw
FROM sys.fn_xe_file_target_read_file(@ReadPath, NULL, NULL, NULL);

-- Shred wait_info events and aggregate by session and wait_type.
SELECT event_data.value('(/event/action[@name="session_id"]/value)[1]', 'int') AS session_id,
       event_data.value('(/event/data[@name="wait_type"]/text)[1]', 'varchar(100)') AS wait_type,
       SUM(event_data.value('(/event/data[@name="duration"]/value)[1]', 'bigint')) AS total_duration,
       SUM(event_data.value('(/event/data[@name="signal_duration"]/value)[1]', 'bigint')) AS total_signal_duration,
       SUM(event_data.value('(/event/data[@name="completed_count"]/value)[1]', 'bigint')) AS total_wait_count
FROM #xe_raw
GROUP BY event_data.value('(/event/action[@name="session_id"]/value)[1]', 'int'),
         event_data.value('(/event/data[@name="wait_type"]/text)[1]', 'varchar(100)')
ORDER BY session_id, total_duration DESC;
GO

-- Teardown when finished. Destructive: drops the session definition.
-- DROP EVENT SESSION WaitCapture ON SERVER;
