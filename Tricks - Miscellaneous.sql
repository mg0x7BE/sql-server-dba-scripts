/**********************************************************************************************/
-- find a specific stored procedure in all databases

sp_MSforeachdb
'select * from ?.information_schema.routines where specific_name = ''Report_PaymentDetail'' and routine_type = ''PROCEDURE'''

/**********************************************************************************************/
-- fix the WMI error
mofcomp "%ProgramFiles(x86)%\Microsoft SQL Server\100\Shared\sqlmgmproviderxpsp2up.mof"

/**********************************************************************************************/
-- error log location
SELECT SERVERPROPERTY('ErrorLogFileName')

/**********************************************************************************************/
-- Show all trace flags
DBCC TRACESTATUS

/**********************************************************************************************/
-- find error codes
SELECT 
    message_id as Error_Code, 
    severity, 
    is_event_logged as Logged_Event, 
    text as Error_Message
FROM sys.messages 
WHERE language_id = 1033
ORDER BY Error_Code;

-- Error Severity

 0 to 9  -- Informational messages
10       -- Informational messages that returns status
         -- information or report non-severe errors
11 to 16 -- Error that can be corrected by the user
17 to 19 -- Software errors that cannot be corrected by the user
20 to 24 -- Serious system errors
25       -- SQL Server service terminating error


/**********************************************************************************************/
-- Find Cached Query Plans By Index Name
DECLARE @Index SYSNAME

SET @Index = '[PK_IndexName]';

WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sqlx) 
SELECT object_name(st.objectid, st.dbid) AS ObjectName,
    qp.query_plan AS QueryPlan,
    st.text AS ObjectText
FROM sys.dm_exec_cached_plans AS cp 
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp 
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st 
WHERE qp.dbid = DB_ID()
AND qp.query_plan.exist('//sqlx:Object[@Index=sql:variable("@Index")]') = 1;

/**********************************************************************************************/
