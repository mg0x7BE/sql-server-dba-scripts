/*
    Diagnostics / Error log
    Read the SQL error log; failed logins and connectivity ring buffers.
*/

-- Current error log file path on disk.
SELECT SERVERPROPERTY('ErrorLogFileName') AS ErrorLogFileName;

-- Read failed logins from the current error log (log 0), newest first.
-- xp_ReadErrorLog still works; the system_health XE session keeps richer, longer login-failure history.
EXEC master..xp_ReadErrorLog 0, 1, N'Failed', N'login', NULL, NULL, N'desc';

-- Look up message text by message_id. language_id 1033 = us_english.
-- Severity ranges: 0-9 informational, 10 status, 11-16 user-correctable,
-- 17-19 software errors, 20-24 serious system errors, 25 service-terminating.
DECLARE @MessageId INT = 18456;  -- 18456 = login failed; set NULL for all
SELECT
    m.message_id      AS Error_Code,
    m.severity,
    m.is_event_logged AS Logged_Event,
    m.text            AS Error_Message
FROM sys.messages AS m
WHERE m.language_id = 1033
    AND (@MessageId IS NULL OR m.message_id = @MessageId)
ORDER BY m.message_id;

-- Enable logging of permission-denied errors. Mutates server config; run deliberately.
-- Message 229 fires on permission failures; WITH_LOG forces it into the error log and Windows event log.
EXEC msdb.dbo.sp_altermessage 229, 'WITH_LOG', 'true';

-- Shred the security-error ring buffer for login-failure detail.
-- Error_Code is hex; resolve the OS code with net helpmsg <decimal> (0x139F is 5023, so net helpmsg 5023).
SELECT
    DATEADD(SECOND, (rbf.[timestamp] - si.ms_ticks) / 1000, GETDATE()) AS Notification_Time,
    r.value('(//SPID)[1]', 'bigint')                      AS SPID,
    r.value('(//ErrorCode)[1]', 'varchar(255)')           AS Error_Code,
    r.value('(//CallingAPIName)[1]', 'varchar(255)')      AS CallingAPIName,
    r.value('(//APIName)[1]', 'varchar(255)')             AS APIName,
    r.value('(//Record/@id)[1]', 'bigint')                AS Record_Id,
    r.value('(//Record/@time)[1]', 'bigint')              AS Record_Time
FROM sys.dm_os_ring_buffers AS rbf
CROSS JOIN sys.dm_os_sys_info AS si
CROSS APPLY (SELECT CAST(rbf.record AS xml)) AS x(r)
WHERE rbf.ring_buffer_type = 'RING_BUFFER_SECURITY_ERROR'
ORDER BY rbf.[timestamp] DESC;

-- Shred the connectivity ring buffer to investigate dropped/failed connections.
-- Useful when clients see connection resets or pre-login failures with no clear error-log entry.
SELECT
    DATEADD(SECOND, (rbf.[timestamp] - si.ms_ticks) / 1000, GETDATE())                    AS Time_Stamp,
    r.value('(//Record/ConnectivityTraceRecord/RecordType)[1]', 'varchar(50)')            AS [Action],
    r.value('(//Record/ConnectivityTraceRecord/RecordSource)[1]', 'varchar(50)')          AS [Source],
    r.value('(//Record/ConnectivityTraceRecord/Spid)[1]', 'int')                          AS SPID,
    r.value('(//Record/ConnectivityTraceRecord/RemoteHost)[1]', 'varchar(100)')           AS RemoteHost,
    r.value('(//Record/ConnectivityTraceRecord/RemotePort)[1]', 'varchar(25)')            AS RemotePort,
    r.value('(//Record/ConnectivityTraceRecord/LocalPort)[1]', 'varchar(25)')             AS LocalPort,
    r.value('(//Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsInputBufferError)[1]', 'varchar(25)')  AS TdsInputBufferError,
    r.value('(//Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsOutputBufferError)[1]', 'varchar(25)') AS TdsOutputBufferError,
    r.value('(//Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsInputBufferBytes)[1]', 'varchar(25)')  AS TdsInputBufferBytes,
    r.value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/PhysicalConnectionIsKilled)[1]', 'int')      AS isPhysConnKilled,
    r.value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/DisconnectDueToReadError)[1]', 'int')        AS DisconnectDueToReadError,
    r.value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/NetworkErrorFoundInInputStream)[1]', 'int')  AS NetworkErrorFound,
    r.value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/ErrorFoundBeforeLogin)[1]', 'int')           AS ErrorBeforeLogin,
    r.value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/SessionIsKilled)[1]', 'int')                 AS isSessionKilled,
    r.value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/NormalDisconnect)[1]', 'int')                AS NormalDisconnect,
    r.value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/NormalLogout)[1]', 'int')                    AS NormalLogout,
    r.value('(//Record/@id)[1]', 'bigint')                                                AS Record_Id,
    r.value('(//Record/@time)[1]', 'bigint')                                              AS Record_Time
FROM sys.dm_os_ring_buffers AS rbf
CROSS JOIN sys.dm_os_sys_info AS si
CROSS APPLY (SELECT CAST(rbf.record AS xml)) AS x(r)
WHERE rbf.ring_buffer_type = 'RING_BUFFER_CONNECTIVITY'
    AND r.value('(//Record/ConnectivityTraceRecord/Spid)[1]', 'int') <> 0
ORDER BY rbf.[timestamp] DESC;
