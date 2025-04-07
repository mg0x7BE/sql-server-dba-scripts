
/**********************************************************************************************/
-- DROP all functions from the database !!! WARNING !!!
SELECT 'DROP FUNCTION [' + SCHEMA_NAME(o.schema_id) + '].[' + o.name + ']'
FROM sys.sql_modules m 
INNER JOIN sys.objects o 
ON m.object_id=o.object_id
WHERE type_desc like '%function%'

/**********************************************************************************************/
-- DROP all procedures from the database !!! WARNING !!!
SELECT 'DROP PROCEDURE [' + SCHEMA_NAME(p.schema_id) + '].[' + p.NAME + ']'
FROM sys.procedures p

/**********************************************************************************************/
/*
    The following query shows DBs which have had no usage since the
    last restart, without relying on query plans being held in the cache,
    as it shows user IO against the indexes (and heaps). This is sort of
    along the lines of using virtual file stats, but the DMV used here
    excludes IO activity from backups. No need to keep a profiler trace
    running, no triggers or auditing required. Of course, if you restart
    your SQL server frequently (or you attach/shutdown databases often)
    this might not be the way to go:
*/

select [name] from sys.databases 
where database_id > 4
AND [name] NOT IN 
(select DB_NAME(database_id) 
from sys.dm_db_index_usage_stats
where coalesce(last_user_seek, last_user_scan, last_user_lookup,'1/1/1970') > 
(select login_time from sysprocesses where spid = 1))

/**********************************************************************************************/
-- OFFLINE all databases !!! WARNING !!!
SELECT '
USE [master]
;' + CHAR(13)+CHAR(10) + '
ALTER DATABASE [' + name + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
;' + CHAR(13)+CHAR(10) + '
USE [master]
;'  + CHAR(13)+CHAR(10) + '
ALTER DATABASE [' + name + '] SET OFFLINE WITH ROLLBACK IMMEDIATE
;'  + CHAR(13)+CHAR(10)
FROM sys.databases WHERE name NOT IN 
( 
	'msdb',
	'model',
	'master',
	'tempdb',
	'msdb',
	'distribution'
)

/**********************************************************************************************/
-- DETACH all databases !!! WARNING !!!
/*
SELECT '
USE [master]
;' + CHAR(13)+CHAR(10) + '
ALTER DATABASE [' + name + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
;' + CHAR(13)+CHAR(10) + '
USE [master]
;'  + CHAR(13)+CHAR(10) + '
EXEC master.dbo.sp_detach_db @dbname = N''' + name + '''
;'  + CHAR(13)+CHAR(10)
FROM sys.databases WHERE name NOT IN 
( 
	'msdb',
	'model',
	'master',
	'tempdb',
	'msdb',
	'distribution'
)
*/

/**********************************************************************************************/
-- Dropping all user-defined stored procs

SELECT 'DROP PROCEDURE [' + SCHEMA_NAME(o.schema_id) + '].[' + o.NAME + ']'
FROM sys.objects o WHERE type = 'p'

/**********************************************************************************************/
-- Dropping all user-defined functions
SELECT 'DROP FUNCTION [' + SCHEMA_NAME(o.schema_id) + '].[' + o.NAME + ']'
FROM sys.objects o where type in ( 'FN', 'IF', 'TF' )

/**********************************************************************************************/
-- Dropping all non-system users from the database.
declare @sql nvarchar(max)
set @sql = ''
SELECT @sql = @sql+
              '
              print ''Dropping '+name+'''
DROP USER [' + ''+name+'' + ']
'
FROM
    sys.database_principals
WHERE
    name NOT IN('dbo','guest','INFORMATION_SCHEMA','sys','public')
  AND TYPE <> 'R'
order by
    name
    execute (@sql)


