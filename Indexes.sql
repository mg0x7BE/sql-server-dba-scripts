/**********************************************************************************************/
-- is there index rebuild in progress?

select command, s.status, login_name, program_name from sys.dm_exec_requests r 
join sys.dm_exec_sessions s on r.session_id = s.session_id 
where r.database_id = DB_ID('SCDX3OD01') and r.session_id <> @@SPID

/**********************************************************************************************/
-- rebuild indexes, smallest first

SELECT 
	db_id() as DBid,
	db_name() as DBname,
	t.object_id as TableObject_id,
	OBJECT_SCHEMA_NAME(t.object_id) AS OBJECT_SCHEMA_NAME,	
    t.NAME AS TableName,
	i.index_id,
    i.name as indexName,
    sum(p.rows) as RowCounts,
    sum(a.total_pages) as TotalPages, 
    sum(a.used_pages) as UsedPages, 
    sum(a.data_pages) as DataPages,
    (sum(a.total_pages) * 8) / 1024 as TotalSpaceMB, 
    (sum(a.used_pages) * 8) / 1024 as UsedSpaceMB, 
    (sum(a.data_pages) * 8) / 1024 as DataSpaceMB,
    fg.name as 'filegroup',
 --   df.physical_name as 'file_name',
    ds.name as 'dataspace',
    'ALTER INDEX ' + i.name + ' ON ' + OBJECT_SCHEMA_NAME(t.object_id) + '.' + t.NAME + ' REBUILD WITH (ONLINE = ON, SORT_IN_TEMPDB = ON, MAXDOP = 1);' as 'SCRIPT'
FROM 
    sys.tables t
JOIN      
    sys.indexes i ON t.OBJECT_ID = i.object_id
JOIN 
    sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
JOIN 
    sys.allocation_units a ON p.partition_id = a.container_id
JOIN
	sys.filegroups fg ON fg.data_space_id = i.data_space_id
JOIN
	sys.database_files df ON df.data_space_id = fg.data_space_id
JOIN
	sys.data_spaces ds ON ds.data_space_id = df.data_space_id
WHERE 
    t.NAME NOT LIKE 'dt%' AND
    i.OBJECT_ID > 255 AND   
    i.type = 2 -- NONCLUSTERED ONLY
GROUP BY 
    t.NAME, i.object_id, i.index_id, i.name, t.object_id, fg.name, ds.name -- ,df.physical_name
ORDER BY SUM(a.total_pages) ASC

/**********************************************************************************************/
-- show filegroup locations

select fg.name,df.physical_name from sys.filegroups fg JOIN sys.database_files df ON df.data_space_id = fg.data_space_id

/**********************************************************************************************/
-- Check the level of fragmentation via sys.dm_db_index_physical_stats

select * from sys.dm_db_index_physical_stats
(
	18,         -- database_id
	1539028764, -- object_id (table or view)
	3,          -- index_id
	NULL,       -- partition_number
	NULL        -- mode
)

/**********************************************************************************************/
-- Return summary information for all indexes of the SalesOrderDetail table

SELECT OBJECT_NAME(P.OBJECT_ID) AS 'Table'
     , I.name AS 'Index'
     , P.index_id AS 'IndexID'
     , P.index_type_desc 
     , P.index_depth 
     , P.page_count 
  FROM sys.dm_db_index_physical_stats (DB_ID(), 
                                       OBJECT_ID('Sales.SalesOrderDetail'), 
                                       NULL, NULL, NULL) P
  JOIN sys.indexes I ON I.OBJECT_ID = P.OBJECT_ID 
                    AND I.index_id = P.index_id;

/**********************************************************************************************/
-- MSDN Returning information about a specified table
/*
	The following example returns size and fragmentation statistics for all indexes and partitions of the Person.Address table. 
	The scan mode is set to 'LIMITED' for best performance and to limit the statistics that are returned. Executing this query requires, 
	at a minimum, CONTROL permission on the Person.Address table.
*/

DECLARE @db_id SMALLINT;
DECLARE @object_id INT;

SET @db_id = DB_ID(N'AdventureWorks2012');
SET @object_id = OBJECT_ID(N'AdventureWorks2012.Person.Address');

IF @db_id IS NULL
BEGIN;
    PRINT N'Invalid database';
END;
ELSE IF @object_id IS NULL
BEGIN;
    PRINT N'Invalid object';
END;
ELSE
BEGIN;
    SELECT * FROM sys.dm_db_index_physical_stats(@db_id, @object_id, NULL, NULL , 'LIMITED');
END;
GO

/**********************************************************************************************/
/*
	This script retrieves information about all indexes associated with a specific table in SQL Server,
	and can be used to identify duplicates
*/
DECLARE @object_name NVARCHAR(255);
DECLARE @schema_name NVARCHAR(255);
SET @object_name = 'my_table_name';
SET @schema_name = 'dbo';

SELECT
    indexes.name AS Index_name,
    indexes.is_unique,
    ISNULL(SUM(dm_db_index_usage_stats.user_seeks), 0) AS user_seeks,
    ISNULL(SUM(dm_db_index_usage_stats.user_scans), 0) AS user_scans,
    ISNULL(SUM(dm_db_index_usage_stats.user_updates), 0) AS user_updates,
    STRING_AGG(CASE WHEN index_columns.is_included_column = 0 THEN columns.name END, ', ')
               WITHIN GROUP (ORDER BY index_columns.index_column_id) AS Index_Columns,
    STRING_AGG(CASE WHEN index_columns.is_included_column = 1 THEN columns.name END, ', ')
               WITHIN GROUP (ORDER BY index_columns.index_column_id) AS Included_Columns
FROM
    sys.indexes AS indexes
        INNER JOIN sys.objects AS objects ON indexes.object_id = objects.object_id
        INNER JOIN sys.schemas AS schemas ON objects.schema_id = schemas.schema_id
        LEFT JOIN sys.dm_db_index_usage_stats AS dm_db_index_usage_stats ON indexes.object_id = dm_db_index_usage_stats.object_id
        AND indexes.index_id = dm_db_index_usage_stats.index_id
        AND dm_db_index_usage_stats.database_id = DB_ID()
        LEFT JOIN sys.index_columns AS index_columns ON indexes.object_id = index_columns.object_id
        AND indexes.index_id = index_columns.index_id
        LEFT JOIN sys.columns AS columns ON index_columns.object_id = columns.object_id
        AND index_columns.column_id = columns.column_id
WHERE
    objects.name = @object_name
  AND schemas.name = @schema_name
GROUP BY
    indexes.name,
    indexes.is_unique
ORDER BY
    6, 7;

/**********************************************************************************************/
-- returns size and fragmentation statistics for all indexes and partitions of the
-- the given table in the AdventureWorks2012 database.

DECLARE @db_id SMALLINT;
DECLARE @object_id INT;

SET @db_id = DB_ID(N'AdventureWorks2012');
SET @object_id = OBJECT_ID(N'AdventureWorks2012.Person.Address');

IF @db_id IS NULL
    BEGIN;
    PRINT N'Invalid database';
    END;
ELSE IF @object_id IS NULL
    BEGIN;
    PRINT N'Invalid object';
    END;
ELSE
    BEGIN;
    SELECT * FROM sys.dm_db_index_physical_stats(@db_id, @object_id, NULL, NULL , 'LIMITED');
    END;
GO

/**********************************************************************************************/
/* ------------------------------------------------------------------
-- Title: FindMissingIndexes
-- Author: Brent Ozar
-- Date: 2009-04-01
-- Modified By: Clayton Kramer ckramer.kramer(at)gmail.com
-- Description: This query returns indexes that SQL Server 2005
-- (and higher) thinks are missing since the last restart. The
-- "Impact" column is relative to the time of last restart and how
-- bad SQL Server needs the index. 10 million+ is high.
-- Changes: Updated to expose full table name. This makes it easier
-- to identify which database needs an index. Modified the
-- CreateIndexStatement to use the full table path and include the
-- equality/inequality columns for easier identifcation.
------------------------------------------------------------------ */

SELECT
    [Impact] = (avg_total_user_cost * avg_user_impact) * (user_seeks + user_scans),
    [Table] = [statement],
    [CreateIndexStatement] = 'CREATE NONCLUSTERED INDEX ix_'
        + sys.objects.name COLLATE DATABASE_DEFAULT
        + '_'
        + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,'')+ISNULL(mid.inequality_columns,''), '[', ''), ']',''), ', ','_')
        + ' ON '
        + [statement]
        + ' ( ' + IsNull(mid.equality_columns, '')
        + CASE WHEN mid.inequality_columns IS NULL THEN '' ELSE
            CASE WHEN mid.equality_columns IS NULL THEN '' ELSE ',' END
                + mid.inequality_columns END + ' ) '
        + CASE WHEN mid.included_columns IS NULL THEN '' ELSE 'INCLUDE (' + mid.included_columns + ')' END
        + ';',
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_group_stats AS migs
         INNER JOIN sys.dm_db_missing_index_groups AS mig ON migs.group_handle = mig.index_group_handle
         INNER JOIN sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle
         INNER JOIN sys.objects WITH (nolock) ON mid.OBJECT_ID = sys.objects.OBJECT_ID
WHERE (migs.group_handle IN
       (SELECT TOP (500) group_handle
        FROM sys.dm_db_missing_index_group_stats WITH (nolock)
        ORDER BY (avg_total_user_cost * avg_user_impact) * (user_seeks + user_scans) DESC))
  AND OBJECTPROPERTY(sys.objects.OBJECT_ID, 'isusertable') = 1
ORDER BY [Impact] DESC , [CreateIndexStatement] DESC


/**********************************************************************************************/
-- Research / troubleshooting

-- 1.1	List all tables
SELECT name as TableName FROM sys.tables

-- 1.2	List all CRM Tables and its row count
SELECT t.name AS TableName, i.rows as Rows
FROM sys.tables AS t INNER JOIN
     sys.sysindexes AS i ON t.object_id = i.id AND i.indid < 2
ORDER BY i.rows DESC


-- 1.3	List all databases excluding system database, all their tables and its row count
EXEC sp_msforeachdb
     'IF ''?'' NOT IN (''master'', ''model'', ''msdb'', ''tempdb'')
     SELECT "?" as DBName, t.name AS TableName, i.rows as Rows
     FROM [?].sys.tables AS t INNER JOIN
     [?].sys.sysindexes AS i ON t.object_id = i.id AND i.indid < 2
     ORDER BY i.rows DESC'


-- 1.4	List indexes applied to the database
SELECT t.name AS TableName, i.name AS IndexName ,i.type_desc AS IndexType
FROM sys.indexes i
         JOIN sys.objects t
              ON i.[object_id] = t.[object_id]
WHERE t.type = 'U' --Only get indexes for User Created Tables
  AND i.name IS NOT NULL
ORDER BY t.name, i.type


-- 1.5	List top most expensive queries on the server
SELECT TOP 10 SUBSTRING(qt.TEXT, (qs.statement_start_offset/2)+1,
                        ((CASE qs.statement_end_offset
                              WHEN -1 THEN DATALENGTH(qt.TEXT)
                              ELSE qs.statement_end_offset
                              END - qs.statement_start_offset)/2)+1),
              qs.execution_count,
              qs.total_logical_reads, qs.last_logical_reads,
              qs.total_logical_writes, qs.last_logical_writes,
              qs.total_worker_time,
              qs.last_worker_time,
              qs.total_elapsed_time/1000000 total_elapsed_time_in_S,
              qs.last_elapsed_time/1000000 last_elapsed_time_in_S,
              qs.last_execution_time,
              qp.query_plan
FROM sys.dm_exec_query_stats qs
         CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
         CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY qs.total_logical_reads DESC -- logical reads
-- ORDER BY qs.total_logical_writes DESC -- logical writes
-- ORDER BY qs.total_worker_time DESC -- CPU time


-- 1.6	List suggestions on what indexes are missing on a SQL Server.
SELECT
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE INDEX [missing_index_' + CONVERT (varchar, mig.index_group_handle) + '_' + CONVERT (varchar, mid.index_handle)
        + '_' + LEFT (PARSENAME(mid.statement, 1), 32) + ']'
        + ' ON ' + mid.statement
        + ' (' + ISNULL (mid.equality_columns,'')
        + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END
        + ISNULL (mid.inequality_columns, '')
        + ')'
        + ISNULL (' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement,
    migs.*, mid.database_id, mid.[object_id]
FROM sys.dm_db_missing_index_groups mig
         INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
         INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
ORDER BY migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC


-- 1.7	List unused indexes since the server last started. May indicate clean up is required.
SELECT OBJECT_NAME(i.[object_id]) AS [Table Name] ,
       i.name
FROM sys.indexes AS i
         INNER JOIN sys.objects AS o ON i.[object_id] = o.[object_id]
WHERE i.index_id NOT IN ( SELECT ddius.index_id
                          FROM sys.dm_db_index_usage_stats AS ddius
                          WHERE ddius.[object_id] = i.[object_id]
                            AND i.index_id = ddius.index_id
                            AND database_id = DB_ID() )
  AND o.[type] = 'U'
ORDER BY OBJECT_NAME(i.[object_id]) ASC ;


-- 1.8	List clustered and non-clustered indexes that are consuming resources in terms of writes and maintenance, but are never being selected for use by the optimizer, so have never been read, at lead since the last time the cache was cleared of accumulated usage data.
SELECT '[' + DB_NAME() + '].[' + su.[name] + '].[' + o.[name] + ']'
                            AS [statement] ,
       i.[name] AS [index_name] ,
       ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups]
                            AS [user_reads] ,
       ddius.[user_updates] AS [user_writes] ,
       SUM(SP.rows) AS [total_rows]
FROM sys.dm_db_index_usage_stats ddius
         INNER JOIN sys.indexes i ON ddius.[object_id] = i.[object_id]
    AND i.[index_id] = ddius.[index_id]
         INNER JOIN sys.partitions SP ON ddius.[object_id] = SP.[object_id]
    AND SP.[index_id] = ddius.[index_id]
         INNER JOIN sys.objects o ON ddius.[object_id] = o.[object_id]
         INNER JOIN sys.sysusers su ON o.[schema_id] = su.[UID]
WHERE ddius.[database_id] = DB_ID() -- current database only
  AND OBJECTPROPERTY(ddius.[object_id], 'IsUserTable') = 1
  AND ddius.[index_id] > 0
GROUP BY su.[name] ,
         o.[name] ,
         i.[name] ,
         ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] ,
         ddius.[user_updates]
HAVING ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] = 0
ORDER BY ddius.[user_updates] DESC ,
         su.[name] ,
         o.[name] ,
         i.[name]
