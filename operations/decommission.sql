/*
    Operations / Decommission
    Generate teardown statements: drop, offline, detach. Destructive.
*/

-- ALL SCRIPTS BELOW ARE DESTRUCTIVE INTENT. They only SELECT/PRINT the
-- statements to run - they do not execute anything. Review output, then
-- run by hand against the correct instance and database.

-- Find databases with no user IO since the instance last started.
-- Useful as a first pass for decommission candidates. Reads index/heap
-- usage from a DMV, so it ignores backup IO and needs no trace.
-- Caveat: sys.dm_db_index_usage_stats is reset on instance restart (and in
-- some versions on index rebuild / db offline), so a "quiet" db here may
-- just mean a recent restart. Confirm uptime before trusting it.
SELECT sqlserver_start_time AS instance_start_time
FROM sys.dm_os_sys_info;

SELECT d.[name]
FROM sys.databases d
WHERE d.database_id > 4
AND d.[name] NOT IN
(
    SELECT DB_NAME(us.database_id)
    FROM sys.dm_db_index_usage_stats us
    WHERE COALESCE(us.last_user_seek, us.last_user_scan, us.last_user_lookup, '1900-01-01')
        > (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)
);
GO

-- Generate KILL statements for every session connected to a target db.
-- Useful to clear connections before setting SINGLE_USER / OFFLINE / DETACH.
-- DESTRUCTIVE: each KILL rolls back the victim session's open transaction.
DECLARE @DatabaseName sysname = N'YourDatabase';

SELECT 'KILL ' + CAST(s.session_id AS varchar(11)) + ';'
    + ' -- ' + ISNULL(s.login_name, '?')
    + ' / ' + ISNULL(s.[program_name], '?')
FROM sys.dm_exec_sessions s
WHERE s.database_id = DB_ID(@DatabaseName)
AND s.session_id <> @@SPID;
GO

-- Generate DROP for all user stored procedures in the current database.
-- DESTRUCTIVE. Run output by hand after review.
USE [YourDatabase];
GO
SELECT 'DROP PROCEDURE [' + SCHEMA_NAME(o.schema_id) + '].[' + o.[name] + '];'
FROM sys.objects o
WHERE o.[type] = 'P';
GO

-- Generate DROP for all user functions in the current database.
-- Covers scalar (FN), inline TVF (IF), multi-statement TVF (TF). DESTRUCTIVE.
USE [YourDatabase];
GO
SELECT 'DROP FUNCTION [' + SCHEMA_NAME(o.schema_id) + '].[' + o.[name] + '];'
FROM sys.objects o
WHERE o.[type] IN ('FN', 'IF', 'TF');
GO

-- Generate DROP USER for non-system database users in the current database.
-- DESTRUCTIVE. Prints only. Limits to user types (S/U/G/E/X) so roles and
-- application roles are skipped; excludes fixed/system principals.
USE [YourDatabase];
GO
SELECT 'PRINT ''Dropping ' + dp.[name] + ''';'
    + CHAR(13) + CHAR(10)
    + 'DROP USER [' + dp.[name] + '];'
FROM sys.database_principals dp
WHERE dp.[type] IN ('S', 'U', 'G', 'E', 'X')
AND dp.is_fixed_role = 0
AND dp.principal_id > 4
AND dp.[name] NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
ORDER BY dp.[name];
GO

-- Generate SINGLE_USER + OFFLINE for all user databases. DESTRUCTIVE:
-- ROLLBACK IMMEDIATE kills active connections. Excludes system/distribution.
-- Useful to quiesce databases before detach or storage reclaim.
SELECT
    'USE [master];' + CHAR(13) + CHAR(10)
    + 'ALTER DATABASE [' + d.[name] + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(13) + CHAR(10)
    + 'ALTER DATABASE [' + d.[name] + '] SET OFFLINE WITH ROLLBACK IMMEDIATE;' + CHAR(13) + CHAR(10)
FROM sys.databases d
WHERE d.[name] NOT IN ('master', 'model', 'msdb', 'tempdb', 'distribution');
GO

-- Generate SINGLE_USER + DETACH for all user databases. DESTRUCTIVE and
-- harder to reverse than OFFLINE - detach removes the db from the instance;
-- you must re-attach from the data/log files to recover. Excludes system dbs.
SELECT
    'USE [master];' + CHAR(13) + CHAR(10)
    + 'ALTER DATABASE [' + d.[name] + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(13) + CHAR(10)
    + 'EXEC master.dbo.sp_detach_db @dbname = N''' + d.[name] + ''';' + CHAR(13) + CHAR(10)
FROM sys.databases d
WHERE d.[name] NOT IN ('master', 'model', 'msdb', 'tempdb', 'distribution');
GO
