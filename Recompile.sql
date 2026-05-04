
/**********************************************************************************************/
/*  RECOMPILE SCRIPT v1.0 / 2014-09-16

	This script marks the stored procedure for recompilation.
	It will automatically retrieve the old + new cached plans (if exists).
	
	Note: it will take more than 1 minute to complete (be patient!)
		  Also please make sure to use the correct database.
*/

DECLARE @stored_proc_name nvarchar(255) 
	SET @stored_proc_name = 'dbo.STORED_PROC_NAME_HERE' -- example: 'dbo.GetInventoryLegFromList'


DECLARE @object_id int
	SET @object_id = OBJECT_ID(@stored_proc_name,'P') -- type: 'P' = SQL Stored Procedure
DECLARE @rowcount int
	
SET NOCOUNT ON;

IF @object_id IS NULL 
	BEGIN;
		PRINT 'Object not found! Invalid database in use?';
	END;
	ELSE
	BEGIN;

		-- fine the old query plan
		SELECT TOP 1 db_name(dbid) as db_name, objectid, objtype, cacheobjtype, usecounts, query_plan as 'old_query_plan'
		FROM sys.dm_exec_cached_plans cp WITH (nolock) CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) x
		WHERE x.objectid = @object_id AND cp.cacheobjtype = 'Compiled plan';
	
		SET @rowcount = @@ROWCOUNT

		-- recompile the stored procedure
		EXEC sp_recompile @stored_proc_name;
		
		IF @rowcount = 1 -- runs only if a cached plan exists
		BEGIN;
			-- wait 1 minute
			WAITFOR DELAY '00:01';
			
			-- find the new query plan
			SELECT TOP 1 db_name(dbid) as db_name, objectid, objtype, cacheobjtype, usecounts, query_plan as 'new_query_plan' 
			FROM sys.dm_exec_cached_plans cp WITH (nolock) CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) x
			WHERE x.objectid = @object_id AND cp.cacheobjtype = 'Compiled plan';		
		END;
		ELSE
			PRINT 'The was no cached plan before recompilation.';
	END;
GO

/**********************************************************************************************/

