/*
    Performance / Plan cache
    Plan cache inspection and forced recompiles.
*/

-- Query Store (performance/query-store.sql) is the durable replacement for plan-cache history and for plan regression/forcing.

-- Cache distribution by cache type and object type. Counts, total/avg use, size.
SELECT cacheobjtype,
       objtype,
       COUNT(*) AS CountOfPlans,
       SUM(usecounts) AS UsageCount,
       SUM(usecounts) / CAST(COUNT(*) AS float) AS AvgUsed,
       SUM(size_in_bytes) / 1024. / 1024. AS SizeInMB
FROM sys.dm_exec_cached_plans
GROUP BY cacheobjtype, objtype
ORDER BY CountOfPlans DESC;

-- Cached plans for one or more objects. Set the OBJECT_IDs to inspect.
DECLARE @object_id1 int = OBJECT_ID(N'dbo.YourObject');  -- second id optional, set NULL to ignore
DECLARE @object_id2 int = NULL;
SELECT cp.usecounts, cp.cacheobjtype, cp.objtype, st.text, qp.query_plan
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE qp.objectid IN (@object_id1, @object_id2)
AND qp.dbid = DB_ID();

-- Search the plan cache by text. Set @search to a fragment of the SQL to find.
DECLARE @search nvarchar(200) = N'%YourSearchString%';
SELECT TOP (50) cp.usecounts, cp.cacheobjtype, cp.objtype,
       OBJECT_NAME(st.objectid, st.dbid) AS ObjectName,
       st.text, qp.query_plan
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE st.text LIKE @search
ORDER BY cp.usecounts DESC;

-- Search the plan cache for plans that use a given index, in the current database.
-- Use before/after an index change to find plans the change touches.
DECLARE @Index sysname = N'[PK_IndexName]';
WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sqlx)
SELECT OBJECT_NAME(st.objectid, st.dbid) AS ObjectName,
       qp.query_plan AS QueryPlan,
       st.text AS ObjectText
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE qp.dbid = DB_ID()
AND qp.query_plan.exist('//sqlx:Object[@Index=sql:variable("@Index")]') = 1;

-- Force a recompile of a stored procedure and capture the cached plan before and after.
-- Run in the procedure's own database. sp_recompile only marks for recompile; it does not flush the cache.
USE [YourDatabase];
GO
SET NOCOUNT ON;
DECLARE @stored_proc_name nvarchar(255) = N'dbo.YourProcedure';
DECLARE @object_id int = OBJECT_ID(@stored_proc_name, 'P');
DECLARE @rowcount int;

IF @object_id IS NULL
BEGIN
    PRINT 'Object not found - wrong database in use?';
END
ELSE
BEGIN
    -- old plan
    SELECT TOP (1) DB_NAME() AS database_name, qp.objectid, cp.objtype, cp.cacheobjtype,
                   cp.usecounts, qp.query_plan AS old_query_plan
    FROM sys.dm_exec_cached_plans AS cp
    CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
    WHERE qp.objectid = @object_id AND qp.dbid = DB_ID() AND cp.cacheobjtype = 'Compiled plan';

    SET @rowcount = @@ROWCOUNT;

    EXEC sp_recompile @stored_proc_name;

    IF @rowcount = 1
    BEGIN
        WAITFOR DELAY '00:01';

        -- new plan
        SELECT TOP (1) DB_NAME() AS database_name, qp.objectid, cp.objtype, cp.cacheobjtype,
                       cp.usecounts, qp.query_plan AS new_query_plan
        FROM sys.dm_exec_cached_plans AS cp
        CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
        WHERE qp.objectid = @object_id AND qp.dbid = DB_ID() AND cp.cacheobjtype = 'Compiled plan';
    END
    ELSE
        PRINT 'No cached plan existed before recompilation.';
END
GO
