/**********************************************************************************************/
-- Connection numbers
select COUNT(*) as 'count', 'number of processes' as 'description' from sys.sysprocesses
UNION ALL
select COUNT(*), 'number of connections' from sys.dm_exec_connections
UNION ALL
select COUNT(*), 'number of sessions' from sys.dm_exec_sessions
order by 2

-- TOP 20 hosts by session numbers
select top 20 host_name, COUNT(*) as 'session count' 
from sys.dm_exec_sessions group by host_name order by 2 desc, 1 asc

/**********************************************************************************************/
-- Active blocking issues?
SELECT [session_id],
		[wait_duration_ms],
		[wait_type],
		[blocking_session_id]
FROM sys.[dm_os_waiting_tasks]
WHERE [wait_type] LIKE N'LCK%';
GO

/**********************************************************************************************/
-- Find what is executing now (+ query plans)

SELECT
	 r.total_elapsed_time AS total_elapsed_time_in_ms
	,r.wait_type
	,r.wait_time
	,r.wait_resource
	,r.last_wait_type
	,r.session_id
	,r.blocking_session_id
	,SUBSTRING(t.text,statement_start_offset/2,
	 (
	CASE
		WHEN statement_end_offset = -1
		THEN LEN(CONVERT(nvarchar(MAX), t.text)) * 2
		ELSE statement_end_offset
	END - statement_start_offset
	 )
	 /2) AS sql_statement_executing_now
	,t.text
	,r.status
	,r.command
	,r.logical_reads
	,r.cpu_time
	,r.reads
	,r.writes
	,s.host_name
	,s.program_name
	,s.login_name
	,s.status
	,s.memory_usage
	,db_name(r.database_id) AS db_name
	,r.plan_handle
	,p.objectid
	,OBJECT_SCHEMA_NAME(p.objectid,p.dbid) AS OBJECT_SCHEMA_NAME
	,object_name(p.objectid,p.dbid) AS object_name
	,p.query_plan
FROM
	sys.dm_exec_requests r
JOIN
	sys.dm_exec_sessions s
ON
	r.session_id = s.session_id 
OUTER APPLY sys.dm_exec_sql_text   (r.sql_handle) t  
OUTER APPLY sys.dm_exec_query_plan (r.plan_handle) p 
WHERE
	r.session_id <> @@spid
AND
(
	r.wait_type      != 'BROKER_RECEIVE_WAITFOR'
	OR       
	r.wait_type IS NULL --filter out service broker waits
)
-- AND s.is_user_process = 1
-- AND r.database_id = DB_ID('')
ORDER BY
	 r.total_elapsed_time DESC -- long running executions
	 --r.logical_reads desc -- high reads i/o
	 --r.cpu_time desc -- high cpu

/**********************************************************************************************/
-- Look at what we waited for

-- Clear historic waits information
DBCC SQLPERF('sys.dm_os_wait_stats',CLEAR)

-- Run a sample work load
WAITFOR DELAY '00:00:30'

-- Look at top waits (ignore the queue waits)
SELECT * FROM sys.dm_os_wait_stats WHERE wait_type NOT IN
('BROKER_TASK_STOP','XE_TIMER_EVENT','SLEEP_TASK','SQLTRACE_BUFFER_FLUSH','LAZYWRITER_SLEEP',
'REQUEST_FOR_DEADLOCK_SEARCH','DBMIRROR_EVENTS_QUEUE','BROKER_TO_FLUSH',
'FT_IFTS_SCHEDULER_IDLE_WAIT','CLR_MANUAL_EVENT') ORDER BY wait_time_ms desc

/**********************************************************************************************/
-- Find long-running transactions
SELECT
	DTST.session_id,
	DTAT.transaction_id AS [Transacton ID],
	[name]      AS [TRANSACTION Name],
	transaction_begin_time AS [TRANSACTION BEGIN TIME],
	DATEDIFF(mi, transaction_begin_time, GETDATE()) AS [Elapsed TIME (in MIN)],
	CASE transaction_type
		WHEN 1 THEN 'Read/write'
		WHEN 2 THEN 'Read-only'
		WHEN 3 THEN 'System'
		WHEN 4 THEN 'Distributed'
	END AS [TRANSACTION Type],
	CASE transaction_state
		WHEN 0 THEN 'The transaction has not been completely initialized yet.'
		WHEN 1 THEN 'The transaction has been initialized but has not started.'
		WHEN 2 THEN 'The transaction is active.'
		WHEN 3 THEN 'The transaction has ended. This is used for read-only transactions.'
		WHEN 4 THEN 'The commit process has been initiated on the distributed transaction. This is for distributed transactions only. The distributed transaction is still active but further processing cannot take place.'
		WHEN 5 THEN 'The transaction is in a prepared state and waiting resolution.'
		WHEN 6 THEN 'The transaction has been committed.'
		WHEN 7 THEN 'The transaction is being rolled back.'
		WHEN 8 THEN 'The transaction has been rolled back.'
	END AS [TRANSACTION Description]
FROM
	sys.dm_tran_active_transactions DTAT
JOIN 
	sys.dm_tran_session_transactions DTST
ON
	DTAT.transaction_id = DTST.transaction_id
WHERE
	[DTST].[is_user_transaction] = 1
ORDER BY
	DTAT.transaction_begin_time

/**********************************************************************************************/