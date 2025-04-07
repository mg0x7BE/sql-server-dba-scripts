
/**********************************************************************************************/
-- step 0: SQL instance:

DECLARE @ts BIGINT;
DECLARE @lastNmin TINYINT;
SET @lastNmin = 100;
SELECT @ts =(SELECT cpu_ticks/(cpu_ticks/ms_ticks) FROM sys.dm_os_sys_info); 
SELECT TOP(@lastNmin)
		SQLProcessUtilization AS [SQLServer_CPU_Utilization], 
		SystemIdle AS [System_Idle_Process], 
		100 - SystemIdle - SQLProcessUtilization AS [Other_Process_CPU_Utilization], 
		DATEADD(ms,-1 *(@ts - [timestamp]),GETDATE())AS [Event_Time] 
FROM (SELECT record.value('(./Record/@id)[1]','int')AS record_id, 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int')AS [SystemIdle], 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int')AS [SQLProcessUtilization], 
[timestamp]      
FROM (SELECT[timestamp], convert(xml, record) AS [record]             
FROM sys.dm_os_ring_buffers             
WHERE ring_buffer_type =N'RING_BUFFER_SCHEDULER_MONITOR'AND record LIKE'%%'
and DATEADD(ms,-1 *(@ts - [timestamp]),GETDATE()) > '10/18/2017  9:07:09 AM'
)AS x )AS y 

ORDER BY record_id DESC;

/**********************************************************************************************/
-- step 1: database:

IF OBJECT_ID('tempdb.dbo.#tbl', 'U') IS NOT NULL
drop table #tbl;

;WITH  DB_CPU AS
(SELECT	DatabaseID, 
		DB_Name(DatabaseID)AS [DatabaseName], 
		SUM(total_worker_time)AS [CPU_Time(Ms)] 
FROM	sys.dm_exec_query_stats AS qs 
CROSS APPLY(SELECT	CONVERT(int, value)AS [DatabaseID]  
			FROM	sys.dm_exec_plan_attributes(qs.plan_handle)  
			WHERE	attribute =N'dbid')AS epa GROUP BY DatabaseID) 
SELECT	GETDATE() reportedtime ,ROW_NUMBER()OVER(ORDER BY [CPU_Time(Ms)] DESC)AS [SNO], 
	DatabaseName AS [DBName], [CPU_Time(Ms)], 
	CAST([CPU_Time(Ms)] * 1.0 /SUM([CPU_Time(Ms)]) OVER()* 100.0 AS DECIMAL(5, 2))AS [CPUPercent] 
INTO #tbl
FROM	DB_CPU 
WHERE	DatabaseID > 4 -- system databases 
	AND DatabaseID <> 32767 -- ResourceDB 
ORDER BY SNO OPTION(RECOMPILE); 

WAITFOR DELAY '00:00:10'

;WITH  DB_CPU AS
(SELECT	DatabaseID, 
		DB_Name(DatabaseID)AS [DatabaseName], 
		SUM(total_worker_time)AS [CPU_Time(Ms)] 
FROM	sys.dm_exec_query_stats AS qs 
CROSS APPLY(SELECT	CONVERT(int, value)AS [DatabaseID]  
			FROM	sys.dm_exec_plan_attributes(qs.plan_handle)  
			WHERE	attribute =N'dbid')AS epa GROUP BY DatabaseID) 
SELECT	a.DatabaseName AS [DBName], 
--a.[CPU_Time(Ms)] - b.[CPU_Time(Ms)] ,
	CAST((a.[CPU_Time(Ms)] - b.[CPU_Time(Ms)]) * 1.0 /SUM((a.[CPU_Time(Ms)] - b.[CPU_Time(Ms)])) OVER()* 100.0 AS DECIMAL(5, 2))AS [CPUPercent] 
FROM	DB_CPU a inner join #tbl b on a.[DatabaseName] = b.[DBName]
WHERE	DatabaseID > 4 -- system databases 
	AND DatabaseID <> 32767 -- ResourceDB 
ORDER BY a.[CPU_Time(Ms)] - b.[CPU_Time(Ms)] DESC OPTION(RECOMPILE);

/**********************************************************************************************/
-- step 2: procedure stats once we got DB:

IF OBJECT_ID('tempdb.dbo.#t', 'U') IS NOT NULL
drop table #t;

SELECT TOP (100) 
  GETDATE() ReportedTime,
  DB_NAME() database_name,
  p.name AS [SP Name], 
  qs.total_worker_time AS [TotalWorkerTime], 
  qs.total_worker_time/qs.execution_count AS [AvgWorkerTime], 
  qs.execution_count, 
  ISNULL(qs.execution_count/DATEDIFF(Second, qs.cached_time, GETDATE()), 0) AS [Calls/Second],
  qs.total_elapsed_time, 
  qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time], 
  qs.cached_time
INTO #t
FROM	sys.procedures AS p WITH (NOLOCK)
INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK) ON p.[object_id] = qs.[object_id]
WHERE qs.database_id = DB_ID()
ORDER BY qs.total_worker_time DESC OPTION (RECOMPILE);

WAITFOR DELAY '00:00:10'

select t.ReportedTime, x.[SP Name], 
DATEDIFF(second, t.ReportedTime, x.ReportedTime),
x.[TotalWorkerTime]-t.[TotalWorkerTime] [TotalWorkerTime],
x.[AvgWorkerTime]-t.[AvgWorkerTime] [AvgWorkerTime],
x.execution_count-t.execution_count execution_count,
x.total_elapsed_time-t.total_elapsed_time total_elapsed_time,
x.[avg_elapsed_time]-t.[avg_elapsed_time] [avg_elapsed_time]
from #t t inner join 
(
SELECT TOP (100) 
  GETDATE() ReportedTime,
  DB_NAME() database_name,
  p.name AS [SP Name], 
  qs.total_worker_time AS [TotalWorkerTime], 
  qs.total_worker_time/qs.execution_count AS [AvgWorkerTime], 
  qs.execution_count, 
  ISNULL(qs.execution_count/DATEDIFF(Second, qs.cached_time, GETDATE()), 0) AS [Calls/Second],
  qs.total_elapsed_time, 
  qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time], 
  qs.cached_time
FROM	sys.procedures AS p WITH (NOLOCK)
INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK) ON p.[object_id] = qs.[object_id]
WHERE qs.database_id = DB_ID()
ORDER BY qs.total_worker_time DESC
) as x on t.[SP Name] = x.[SP Name]
order by x.[TotalWorkerTime]-t.[TotalWorkerTime] desc

/**********************************************************************************************/
-- Total waits are wait_time_ms (high signal waits indicate CPU pressure)
DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);
GO

SELECT CAST(100.0 * SUM(signal_wait_time_ms) / SUM(wait_time_ms)
AS NUMERIC(20,2)) AS[%signal (cpu) waits] ,
CAST(100.0 * SUM(wait_time_ms -signal_wait_time_ms)
/ SUM(wait_time_ms) AS NUMERIC(20,2)) AS[%resource waits]
FROM  sys.dm_os_wait_stats ;
GO

/**********************************************************************************************/
-- Perfmon approach (a bit crazy):

--	1)	Type perfmon in a Windows CMD prompt or launch from Control Panel.
--		Click on Add counters and select the "Thread" object in the drop down.
--		Select these counters at the same time:

--		% Processor Time
--		ID Thread
--		Thread State
--		Thread Wait Reason

--		select all of the instances that begin with "sqlservr" from the list box

/**********************************************************************************************/
--	2)	Press (Ctrl+R) or click on the view Report tab to change from graphical to report view

/**********************************************************************************************/
--	3)	Identify which thread is causing the problem.
--		Notice ID Thread and % Processor Time

/**********************************************************************************************/
--	4)	Correlate the Thread ID (KPID) identified in the last step to the SPID. 
--		To do this, run the following query in Query analyzer:

  		SELECT spid, kpid, dbid, cpu, memusage FROM sys.sysprocesses WHERE kpid = (ID Thread)

/**********************************************************************************************/
--	5)  To find how many threads and open transactions this is running, run this query.

  		SELECT spid, kpid, status, cpu, memusage, open_tran, dbid FROM sys.sysprocesses WHERE spid = (SPID)

/**********************************************************************************************/
--	6)  To get the exact query that is running,run DBCC INPUTBUFFER using the SPID	

  		DBCC INPUTBUFFER(SPID)

/**********************************************************************************************/