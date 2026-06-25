/*
    Diagnostics / Deadlocks
    Capture and read deadlock graphs from system_health.
*/

-- Recent deadlock graphs from the system_health ring buffer target.
-- Always on by default, no trace flags needed. Fastest first look after a deadlock report.
-- Ring buffer is small and rolls over; for older events read the .xel files below.
SELECT
    CAST(xevent.value('(@timestamp)[1]', 'datetime') AS datetime2) AS event_time_utc,
    CAST(xevent.query('(data[@name="xml_report"]/value/deadlock)[1]') AS xml) AS deadlock_graph
FROM (
    SELECT CAST(target_data AS xml) AS target_xml
    FROM sys.dm_xe_session_targets st
    JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
    WHERE s.name = 'system_health'
      AND st.target_name = 'ring_buffer'
) AS rb
CROSS APPLY target_xml.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS x(xevent)
ORDER BY event_time_utc DESC;

-- Deadlock graphs from the system_health .xel files (longer history than the ring buffer).
-- Wildcard path picks up all rollover files; leave file/offset NULL to read the whole set.
-- Default location below is the standard install path - adjust to your instance.
DECLARE @SystemHealthPath nvarchar(260) = N'system_health*.xel';   -- relies on the default Log directory

SELECT
    CAST(event_xml.value('(event/@timestamp)[1]', 'datetime') AS datetime2) AS event_time_utc,
    CAST(event_xml.query('event/data[@name="xml_report"]/value/deadlock') AS xml) AS deadlock_graph
FROM (
    SELECT CAST(event_data AS xml) AS event_xml
    FROM sys.fn_xe_file_target_read_file(@SystemHealthPath, NULL, NULL, NULL)
) AS f
WHERE event_xml.value('(event/@name)[1]', 'sysname') = 'xml_deadlock_report'
ORDER BY event_time_utc DESC;

-- Shred one deadlock graph into victim / processes / resources.
-- Paste a single <deadlock>...</deadlock> graph from the queries above into @graph.
-- victim_process_id matches the process whose @id equals the <victim-list> victimProcess.
DECLARE @graph xml = N'<deadlock>...paste a single deadlock graph here...</deadlock>';

SELECT
    @graph.value('(deadlock/victim-list/victimProcess/@id)[1]', 'nvarchar(50)') AS victim_process_id;

-- Processes involved.
SELECT
    p.value('@id', 'nvarchar(50)')              AS process_id,
    p.value('@spid', 'int')                     AS spid,
    p.value('@loginname', 'nvarchar(128)')      AS login_name,
    p.value('@hostname', 'nvarchar(128)')       AS host_name,
    p.value('@clientapp', 'nvarchar(256)')      AS client_app,
    p.value('@isolationlevel', 'nvarchar(64)')  AS isolation_level,
    p.value('@waitresource', 'nvarchar(256)')   AS wait_resource,
    p.value('@transactionname', 'nvarchar(128)') AS transaction_name,
    p.value('@lockMode', 'nvarchar(20)')        AS lock_mode,
    p.value('(executionStack/frame)[1]', 'nvarchar(max)') AS last_frame,
    p.value('(inputbuf)[1]', 'nvarchar(max)')   AS input_buffer
FROM @graph.nodes('deadlock/process-list/process') AS t(p);

-- Resources fought over (which object/index and the lock owners vs waiters).
SELECT
    r.value('local-name(.)[1]', 'nvarchar(50)') AS resource_type,
    r.value('@objectname', 'nvarchar(256)')     AS object_name,
    r.value('@indexname', 'nvarchar(256)')      AS index_name,
    r.value('@mode', 'nvarchar(20)')            AS request_mode,
    o.value('@id', 'nvarchar(50)')              AS owner_process_id,
    o.value('@mode', 'nvarchar(20)')            AS owner_mode,
    w.value('@id', 'nvarchar(50)')              AS waiter_process_id,
    w.value('@mode', 'nvarchar(20)')            AS waiter_mode
FROM @graph.nodes('deadlock/resource-list/*') AS t(r)
OUTER APPLY r.nodes('owner-list/owner') AS ol(o)
OUTER APPLY r.nodes('waiter-list/waiter') AS wl(w);
GO

-- Dedicated XE session that writes deadlock graphs to a .xel file.
-- Use when you need durable, isolated history beyond what system_health keeps.
-- Adjust the target path; the folder must exist and the service account must be able to write to it.
-- DROP first is destructive only to this capture session - it removes prior buffered events.
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'capture_deadlocks')
    DROP EVENT SESSION capture_deadlocks ON SERVER;
GO

CREATE EVENT SESSION capture_deadlocks ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file (
    SET filename = N'capture_deadlocks.xel',   -- relative path lands in the default Log directory
        max_file_size = 50,                    -- MB per rollover file
        max_rollover_files = 5
)
WITH (STARTUP_STATE = ON);
GO

-- Start the session (no events are captured until it is started).
ALTER EVENT SESSION capture_deadlocks ON SERVER STATE = START;
GO

-- Read deadlock graphs back from the custom session files.
DECLARE @CaptureFile nvarchar(260) = N'capture_deadlocks*.xel';

SELECT
    CAST(event_xml.value('(event/@timestamp)[1]', 'datetime') AS datetime2) AS event_time_utc,
    CAST(event_xml.query('event/data[@name="xml_report"]/value/deadlock') AS xml) AS deadlock_graph
FROM (
    SELECT CAST(event_data AS xml) AS event_xml
    FROM sys.fn_xe_file_target_read_file(@CaptureFile, NULL, NULL, NULL)
) AS f
ORDER BY event_time_utc DESC;
GO

-- Stop and remove the custom session when done. Destructive: drops the session definition.
-- ALTER EVENT SESSION capture_deadlocks ON SERVER STATE = STOP;
-- DROP EVENT SESSION capture_deadlocks ON SERVER;

-- Legacy: trace flags 1204 (by node) and 1222 (by process and resource) still write deadlock
-- detail to the error log via DBCC TRACEON (1204, 1222) / DBCC TRACESTATUS. system_health XE above
-- replaces them - prefer the XE graphs.
