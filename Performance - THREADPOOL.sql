/**********************************************************************************************/
-- Analyze all current executing requests inside SQL Server
select
	r.command,
	r.plan_handle,
	r.wait_type,
	r.wait_resource,
	r.wait_time,
	r.session_id,
	r.blocking_session_id
from sys.dm_exec_requests r
join sys.dm_exec_sessions s on s.session_id = r.session_id
where s.is_user_process = 1

/**********************************************************************************************/
-- Analyze all requests which are currently waiting for a free worker thread
select * from sys.dm_os_waiting_tasks
where wait_type = 'THREADPOOL'

/**********************************************************************************************/
-- Analyze the head blocker session
select
	login_time,
	[host_name],
	[program_name],
	login_name
from sys.dm_exec_sessions
where session_id = 54

/**********************************************************************************************/
-- Analyze the head blocker connection
SELECT 
	connect_time,
	client_tcp_port,
	most_recent_sql_handle
FROM sys.dm_exec_connections
WHERE session_id = 54

/**********************************************************************************************/
-- Retrieve the SQL statement
SELECT [text] from sys.dm_exec_sql_text(0x0100040064540D33C01210077E02000000000000000000000000000000000000000000000000000000000000)


