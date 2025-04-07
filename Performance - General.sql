/**********************************************************************************************/
-- show only active connections:
sp_who2 'active';

/**********************************************************************************************/
-- Top 10 Worst Performing Queries
SELECT TOP 10 
	execution_count as [Number of Executions],
	total_worker_time/execution_count as [Average CPU Time],
	Total_Elapsed_Time/execution_count as [Average Elapsed Time],
	(
		SELECT 
			SUBSTRING(text,statement_start_offset/2,
						(CASE WHEN statement_end_offset = -1
						THEN LEN(CONVERT(nvarchar(max), [text])) * 2
						ELSE statement_end_offset 
						END - statement_start_offset) /2)
		FROM sys.dm_exec_sql_text(sql_handle)
	) as query_text
FROM 
	sys.dm_exec_query_stats
ORDER BY 
	[Average CPU Time] DESC;

/**********************************************************************************************/
-- most use of tempdb - five executing tasks
SELECT top 5 * FROM sys.dm_db_session_space_usage
ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC

/**********************************************************************************************/
-- space in tempdb
SELECT	
			SD.name,
			MF.database_id,
			SUM( CONVERT(decimal(10,2),(DF.size/128.0)) ) as Size,  
			SUM( CONVERT(decimal(10,2), (CAST(FILEPROPERTY(DF.name, 'SpaceUsed') AS INT)/128.0 ) ) ) AS UsedSpace
	FROM sys.master_files MF JOIN sys.databases SD
		ON SD.database_id = MF.database_id 
	JOIN sys.database_files DF
		ON DF.physical_name collate DATABASE_DEFAULT = MF.physical_name collate DATABASE_DEFAULT
	WHERE MF.type = 0 
	GROUP BY SD.name, MF.database_id

/**********************************************************************************************/
-- show only user connections that have performed a write operations:
	SELECT 
		* 
	FROM
		sys.dm_exec_sessions
	WHERE 
		is_user_process = 1
	AND 
		writes > 0;

/**********************************************************************************************/
-- detecting SQL Server blocking
select * from sys.dm_os_waiting_tasks
select * from sys.dm_os_wait_stats
select * from sys.dm_tran_locks

/**********************************************************************************************/
-- dm_os_performance_counters
SELECT
	[counter_name] = RTRIM([counter_name]),
	[cntr_value],
	[instance_name],
	[description] = CASE [counter_name] 
	WHEN 'Batch Requests/sec'  ------------------------------------------------------------------------------------------------
		THEN 'Number of batches SQL Server is receiving per second. 
			  This counter is a good indicator of how much activity is being processed by your SQL Server box. 
			  The higher the number, the more queries are being executed on your box.'			 
	WHEN 'Buffer cache hit ratio' ---------------------------------------------------------------------------------------------
		THEN 'How often SQL Server is able to find data pages in its buffer cache when a query needs a data page. 
			  The higher this number the better, because it means SQL Server was able to get data for 
			  queries out of memory instead of reading from disk. 
			  You want this number to be as close to 100 as possible. 
			  Having this counter at 100 means that 100% of the time SQL Server has found the needed data pages in memory. 
			  A low buffer cache hit ratio could indicate a memory problem.'
	WHEN 'Buffer cache hit ratio base' ----------------------------------------------------------------------------------------
		THEN 'Base value - divisor to calculate the hit ratio percentage'
	WHEN 'Checkpoint pages/sec' -----------------------------------------------------------------------------------------------
		THEN 'Number of pages written to disk by a checkpoint operation. 
		      You should watch this counter over time to establish a baseline for your systems. 
		      Once a baseline value has been established you can watch this value to see if it is climbing. 
		      If this counter is climbing, it might mean you are running into memory pressures that are causing 
		      dirty pages to be flushed to disk more frequently than normal.'	
	WHEN 'Dist:Delivery Latency' ----------------------------------------------------------------------------------------------
		THEN 'Latency (ms) from Distributor to Subscriber'
	WHEN 'Free pages' ---------------------------------------------------------------------------------------------------------
		THEN 'Total number of free pages on all free lists. Minimum values below 640 indicate memory pressure'
	WHEN 'Lock Waits/sec' -----------------------------------------------------------------------------------------------------
		THEN 'Number of times per second that SQL Server is not able to retain a lock right away for a resource. 
		      You want to keep this counter at zero, or close to zero at all times.'
	WHEN 'Logreader:Delivery Latency' -----------------------------------------------------------------------------------------
		THEN 'Latency (ms) from Publisher to Distributor'
	WHEN 'Page life expectancy' -----------------------------------------------------------------------------------------------
		THEN 'How long pages stay in the buffer cache in seconds. 
			  The longer a page stays in memory, the more likely server will not need to read from HDD to resolve a query. 
			  Some say anything below 300 (or 5 minutes) means you might need additional memory.'
	WHEN 'Page Splits/sec' ----------------------------------------------------------------------------------------------------
		THEN 'Number of times SQL Server had to split a page when updating or inserting data per second. 
			  Page splits are expensive, and cause your table to perform more poorly due to fragmentation. 
			  Therefore, the fewer page splits you have the better your system will perform. 
			  Ideally this counter should be less than 20% of the batch requests per second.'
	WHEN 'Processes blocked' --------------------------------------------------------------------------------------------------
		THEN 'Number of blocked processes. 
			  When one process is blocking another process, the blocked process cannot move forward with 
			  its execution plan until the resource that is causing it to wait is freed up. 
			  Ideally you don''t want to see any blocked processes. 
			  When processes are being blocked you should investigate.'
	WHEN 'SQL Compilations/sec' -----------------------------------------------------------------------------------------------
		THEN 'Number of times SQL Server compiles an execution plan per second. 
			  Compiling an execution plan is a resource-intensive operation. 
			  Compilations/Sec should be compared with the number of Batch Requests/Sec to get an indication 
			  of whether or not complications might be hurting your performance. 
			  To do that, divide the number of batch requests by the number of compiles per second 
			  to give you a ratio of the number of batches executed per compile. 
			  Ideally you want to have one compile per every 10 batch requests.'
	WHEN 'SQL Re-Compilations/sec' --------------------------------------------------------------------------------------------
		THEN 'Number of times a re-compile event was triggered per second.
			  When the execution plan is invalidated due to some significant event, SQL Server will re-compile it. 
			  Re-compiles, like compiles, are expensive operations so you want to minimize the number of re-compiles. 
			  Ideally you want to keep this counter less than 10% of the number of Compilations/Sec.'
	WHEN 'User Connections' ---------------------------------------------------------------------------------------------------
		THEN 'Number of different users that are connected to SQL Server at the time the sample was taken. 
			  You need to watch this counter over time to understand your baseline user connection numbers. 
			  Once you have some idea of your high and low water marks during normal usage of your system, 
			  you can then look for times when this counter exceeds the high and low marks. 
			  If the value of this counter goes down and the load on the system is the same, 
			  then you might have a bottleneck that is not allowing your server to handle the normal load.'												
	ELSE ''	
	END
FROM 
	sys.dm_os_performance_counters
WHERE 
	[counter_name]
IN
(
	'Buffer cache hit ratio',
	'Buffer cache hit ratio base',
	'Page life expectancy', 
	'Batch Requests/Sec',
	'SQL Compilations/Sec',
	'SQL Re-Compilations/Sec',
	'User Connections',
	'Page Splits/sec',
	'Processes blocked',
	'Free pages',
	'Checkpoint pages/sec',
	'Logreader:Delivery Latency',
	'Dist:Delivery Latency'
)
AND
	[object_name] NOT LIKE '%Partition%' 
AND
	[object_name] NOT LIKE '%Node%'
OR
(
	[counter_name] = 'Lock Waits/sec'
	AND
	[instance_name] = '_Total'
)
ORDER BY 1

/**********************************************************************************************/
-- Filter the currently executing requests
SELECT s.original_login_name, s.program_name, r.command, 
       r.wait_type, r.wait_time, r.blocking_session_id, r.sql_handle
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
ON r.session_id = s.session_id		
WHERE s.is_user_process = 1;
GO

/**********************************************************************************************/
-- Also retrieve details of the SQL Batch that
-- is being executed, instead of just the handle
SELECT s.original_login_name, s.program_name, r.command, t.text,
       r.wait_type, r.wait_time, r.blocking_session_id
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
ON r.session_id = s.session_id		
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1;
GO

/**********************************************************************************************/
-- Find the actual statement that is being executed rather than the batch.
SELECT s.original_login_name, s.program_name,  r.command, 
       (SELECT TOP (1) SUBSTRING(t.text, r.statement_start_offset / 2 + 1, 
			                     ((CASE WHEN r.statement_end_offset = -1 
                                   THEN (LEN(CONVERT(nvarchar(max), t.text)) * 2) 
                                   ELSE r.statement_end_offset 
                                   END)  - r.statement_start_offset) / 2 + 1)) AS SqlStatement,
       r.wait_type, r.wait_time, r.blocking_session_id
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text (r.sql_handle) AS t		
WHERE s.is_user_process = 1;
GO

/**********************************************************************************************/
-- How the procedure cache is distributed
SELECT cacheobjtype, 
       objtype , 
       COUNT(*) as CountofPlans, 
       SUM(usecounts) as UsageCount,
       SUM(usecounts)/CAST(count(*)as float) as AvgUsed , 
       SUM(size_in_bytes)/1024./1024. as SizeinMB
FROM sys.dm_exec_cached_plans
GROUP BY cacheobjtype, objtype
ORDER BY CountOfPlans DESC;
GO

/**********************************************************************************************/
-- Top 10 queries based on Average Reads
SELECT TOP (10) total_logical_reads/execution_count AS AvgReads,
                SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
                ((CASE statement_end_offset 
                  WHEN -1 THEN DATALENGTH(st.text)
                  ELSE qs.statement_end_offset END 
                 - qs.statement_start_offset)/2) + 1) as StatementText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY total_logical_reads/execution_count DESC;
GO

/**********************************************************************************************/
-- I/O statistics for the database files
SELECT DB_NAME(fs.database_id) AS DatabaseName,
       mf.name AS FileName,
       mf.type_desc,
       fs.*
FROM sys.dm_io_virtual_file_stats(NULL,NULL) AS fs
INNER JOIN sys.master_files AS mf
ON fs.database_id = mf.database_id
AND fs.file_id = mf.file_id
ORDER BY fs.database_id, fs.file_id DESC;
GO

/**********************************************************************************************/
-- General wait statistics
SELECT * FROM sys.dm_os_wait_stats;
GO

/**********************************************************************************************/
-- more troubleshooting

-- Returns details of every connection to the server.
SELECT * FROM sys.dm_exec_connections;
GO

-- Returns details of every session on the server.
SELECT * FROM sys.dm_exec_sessions;
GO

-- Returns details of current requests that are executing.
SELECT * FROM sys.dm_exec_requests;
GO

/**********************************************************************************************/
-- Shows when users connected and when they last finished
-- executing a request
SELECT s.session_id, s.login_name, c.connect_time, s.last_request_end_time 
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r
ON s.session_id = r.session_id 
INNER JOIN sys.dm_exec_connections AS c
ON s.session_id = c.session_id 
WHERE s.is_user_process = 1;
GO

/**********************************************************************************************/
-- Shows the SQL batches being executed
SELECT s.session_id, s.login_name, st.text  
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r
ON s.session_id = r.session_id 
INNER JOIN sys.dm_exec_connections AS c
ON s.session_id = c.session_id 
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE s.is_user_process = 1;
GO

/**********************************************************************************************/
-- Shows the SQL batches being executed and
-- the execution plans
SELECT s.session_id, s.login_name, st.text, qp.query_plan 
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r
ON s.session_id = r.session_id 
INNER JOIN sys.dm_exec_connections AS c
ON s.session_id = c.session_id 
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
WHERE s.is_user_process = 1;
GO

/**********************************************************************************************/
-- view the blocked processes
SELECT r.session_id, r.status, r.blocking_session_id,
       r.command, r.wait_type, r.wait_time,	t.text
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t 
WHERE r.blocking_session_id > 1;
GO

/**********************************************************************************************/
-- Find the head of the blocking chain
SELECT DISTINCT blocking_session_id
FROM sys.dm_exec_requests AS r
WHERE NOT EXISTS (SELECT 1 
                  FROM sys.dm_exec_requests r2
                  WHERE r.blocking_session_id = r2.session_id
                  AND r2.blocking_session_id > 0)
AND r.blocking_session_id > 0							;
GO

/**********************************************************************************************/
-- Find the code being executed by the head of the 
-- blocking chain by using the previous query as a
-- subquery
SELECT t.text 
FROM sys.dm_exec_connections AS c
CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) AS t 
WHERE c.session_id = (SELECT DISTINCT blocking_session_id
                      FROM sys.dm_exec_requests AS r
                      WHERE NOT EXISTS (SELECT 1 
                                        FROM sys.dm_exec_requests r2
                                        WHERE r.blocking_session_id = r2.session_id
                                        AND r2.blocking_session_id > 0)
                      AND r.blocking_session_id > 0);
GO

/**********************************************************************************************/
-- long running processes
select
    p.spid
,   right(convert(varchar, 
            dateadd(ms, datediff(ms, P.last_batch, getdate()), '1900-01-01'), 
            121), 12) as 'batch_duration'
,   P.program_name
,   P.hostname
,   P.loginame
from master.dbo.sysprocesses P
where P.spid > 50
and      P.status not in ('background', 'sleeping')
and      P.cmd not in ('AWAITING COMMAND'
                    ,'MIRROR HANDLER'
                    ,'LAZY WRITER'
                    ,'CHECKPOINT SLEEP'
                    ,'RA MANAGER')
order by batch_duration desc


