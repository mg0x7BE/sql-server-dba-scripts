/*****************************************************************************************************/
-- Replication agent waits / Find wait_types for specific session

-- [ 1 ] -- Find Distribution Agent Session ID
SELECT session_id, program_name, reads, writes, logical_reads, db_name(database_id)
FROM sys.dm_exec_sessions
WHERE program_name LIKE 'Replication%';
GO

-- [ 2 ] -- Event session to track waits by session
CREATE EVENT SESSION Replication_AGT_Waits
ON SERVER
ADD EVENT sqlos.wait_info(
	ACTION (sqlserver.session_id)
	WHERE (
	-- [package0].[equal_uint64]([sqlserver].[session_id],(61)) OR
	   [package0].[equal_uint64]([sqlserver].[session_id],(61)))) -- Distribution Agent Session ID
	ADD TARGET package0.asynchronous_file_target
	(SET FILENAME = N'C:\SQLskills\ReplAGTStats.xel', -- CHECK that these are cleared
	METADATAFILE = N'C:\SQLskills\ReplAGTStats.xem');

-- [ 3 ] --
ALTER EVENT SESSION Replication_AGT_Waits
ON SERVER STATE = START;
GO
ALTER EVENT SESSION Replication_AGT_Waits
ON SERVER STATE = STOP;
GO

-- DROP EVENT SESSION Replication_AGT_Waits ON SERVER

-- [ 4 ] --

-- Raw data into intermediate table
-- (Make sure you've cleared out previous target files!)
SELECT CAST(event_data as XML) event_data
INTO #ReplicationAgentWaits_Stage_1
FROM sys.fn_xe_file_target_read_file
	('C:\SQLskills\ReplAGTStats*.xel',
	 'C:\SQLskills\ReplAGTStats*.xem',
	 NULL, NULL);

-- [ 5 ] --
	 
-- Aggregated data into intermediate table
-- #ReplicationAgentWaits
SELECT
	event_data.value
	('(/event/action[@name=''session_id'']/value)[1]', 'smallint') as session_id, event_data.value
	('(/event/data[@name=''wait_type'']/text)[1]', 'varchar(100)') as wait_type, event_data.value
	('(/event/data[@name=''duration'']/value)[1]', 'bigint') as duration, event_data.value
	('(/event/data[@name=''signal_duration'']/value)[1]', 'bigint') as signal_duration, event_data.value
	('(/event/data[@name=''completed_count'']/value)[1]', 'bigint') as completed_count
INTO #ReplicationAgentWaits_Stage_2
FROM #ReplicationAgentWaits_Stage_1;

-- [ 6 ] --

-- Final result set
SELECT session_id,
	wait_type,
	SUM(duration) total_duration,
	SUM(signal_duration) total_signal_duration,
	SUM(completed_count) total_wait_count
FROM #ReplicationAgentWaits_Stage_2
GROUP BY session_id, wait_type
ORDER BY session_id, SUM(duration) DESC;
GO

/*****************************************************************************************************/
