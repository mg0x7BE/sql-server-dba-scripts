/**********************************************************************************************/
-- shows running traces
SELECT * FROM sys.traces

--shws running traces (old)
SELECT * FROM sys.fn_trace_getinfo(0) ;

-- stops the trace
EXEC sp_trace_setstatus @traceid = 2 , @status = 0

-- stops and removes the trace
EXEC sp_trace_setstatus @traceid = 2 , @status = 2

/**********************************************************************************************/
-- Default Trace

-- Is the default trace running
SELECT * FROM sys.configurations WHERE configuration_id = 1568

-- find the location 
SELECT *  FROM fn_trace_getinfo(default)  

-- directly query the data 
SELECT *  
FROM fn_trace_gettable('G:\mhcrpmmdq532_sysdbs_01\SQLDAT\MSSQL10.PRTOLPRD01\MSSQL\Log\log_9.trc',default) 
ORDER BY starttime desc

/**********************************************************************************************/
-- SQL Trace

DECLARE @TraceID int = 2; --Replace with correct TraceID
-- Stop the trace. Note that you must change the trace id here
-- from 2 to whatever value was returned when the trace
-- was started.
-- Note: the status 0 stops the trace. The status 2 closes the
--       file and deletes the trace definition on the server.
EXEC sp_trace_setstatus @TraceID, 0;
EXEC sp_trace_setstatus @TraceID, 2;
GO

/**********************************************************************************************/