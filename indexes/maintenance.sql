/*
    Indexes / Maintenance
    Index fragmentation, rebuild and reorganize, and fill factor.
*/

-- Index rebuild/reorganize currently running on this database.
-- Run before starting maintenance so you do not collide with an in-flight job.
USE [YourDatabase];
GO
SELECT  r.session_id,
        r.command,
        s.status,
        s.login_name,
        s.program_name,
        r.percent_complete,
        r.wait_type,
        DB_NAME(r.database_id) AS database_name
FROM    sys.dm_exec_requests   r
JOIN    sys.dm_exec_sessions   s ON s.session_id = r.session_id
WHERE   r.database_id = DB_ID()
  AND   r.command LIKE '%INDEX%'
  AND   r.session_id <> @@SPID;
GO

-- List indexes applied to the current database.
-- Quick inventory before deciding what to maintain.
USE [YourDatabase];
GO
SELECT  s.name  AS schema_name,
        t.name  AS table_name,
        i.name  AS index_name,
        i.type_desc AS index_type,
        i.fill_factor
FROM    sys.indexes i
JOIN    sys.objects t ON t.object_id = i.object_id
JOIN    sys.schemas s ON s.schema_id = t.schema_id
WHERE   t.type = 'U'
  AND   i.name IS NOT NULL
ORDER BY s.name, t.name, i.type_desc;
GO

-- Index sizes for the current database, smallest first.
-- Use to plan rebuild order (do the cheap ones first) and to spot bloat.
USE [YourDatabase];
GO
SELECT  s.name  AS schema_name,
        t.name  AS table_name,
        i.index_id,
        i.name  AS index_name,
        i.type_desc AS index_type,
        SUM(ps.row_count)                  AS row_count,
        SUM(ps.reserved_page_count) * 8 / 1024 AS reserved_mb,
        SUM(ps.used_page_count)     * 8 / 1024 AS used_mb
FROM    sys.dm_db_partition_stats ps
JOIN    sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
JOIN    sys.tables  t ON t.object_id = i.object_id
JOIN    sys.schemas s ON s.schema_id = t.schema_id
WHERE   i.index_id > 0          -- skip heaps
GROUP BY s.name, t.name, i.index_id, i.name, i.type_desc
ORDER BY reserved_mb ASC;
GO

-- Filegroup to physical file mapping.
-- Useful when a rebuild needs space or you are moving indexes between filegroups.
USE [YourDatabase];
GO
SELECT  fg.name AS filegroup_name,
        df.name AS logical_file_name,
        df.physical_name
FROM    sys.filegroups fg
JOIN    sys.database_files df ON df.data_space_id = fg.data_space_id
ORDER BY fg.name;
GO

-- Fragmentation for a single index via sys.dm_db_index_physical_stats.
-- Targeted check when you already know the table/index; LIMITED mode is cheap.
USE [YourDatabase];
GO
DECLARE @object_id INT = OBJECT_ID(N'dbo.YourTable');
DECLARE @index_id  INT = NULL;   -- NULL = all indexes on the object
SELECT  OBJECT_NAME(ps.object_id) AS table_name,
        i.name                    AS index_name,
        ps.index_id,
        ps.index_type_desc,
        ps.index_depth,
        ps.page_count,
        ps.avg_fragmentation_in_percent
FROM    sys.dm_db_index_physical_stats(DB_ID(), @object_id, @index_id, NULL, 'LIMITED') ps
JOIN    sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
ORDER BY ps.avg_fragmentation_in_percent DESC;
GO

-- Fragmentation across the whole current database with a rebuild-vs-reorganize decision.
-- Common rule: 5-30 pct reorganize, over 30 pct rebuild; ignore tiny indexes (< 1000 pages).
-- LIMITED scan keeps this affordable on large databases.
USE [YourDatabase];
GO
DECLARE @min_page_count INT = 1000;
SELECT  s.name AS schema_name,
        t.name AS table_name,
        i.name AS index_name,
        ps.index_type_desc,
        ps.partition_number,
        ps.page_count,
        ps.avg_fragmentation_in_percent,
        CASE
            WHEN ps.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
            WHEN ps.avg_fragmentation_in_percent >= 5 THEN 'REORGANIZE'
            ELSE 'NONE'
        END AS recommended_action
FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN    sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
JOIN    sys.tables  t ON t.object_id = i.object_id
JOIN    sys.schemas s ON s.schema_id = t.schema_id
WHERE   i.index_id > 0
  AND   i.name IS NOT NULL
  AND   ps.page_count >= @min_page_count
ORDER BY ps.avg_fragmentation_in_percent DESC;
GO

-- Generate ALTER INDEX statements from fragmentation, generate-and-print only.
-- Review the output, then run the statements you want. Nothing executes here.
-- REBUILD uses ONLINE=ON, RESUMABLE=ON so the operation can be paused and resumed;
-- on 2025 optimized locking further reduces lock footprint and blocking during online rebuilds.
USE [YourDatabase];
GO
DECLARE @min_page_count INT = 1000;
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    i.name AS index_name,
    ps.avg_fragmentation_in_percent,
    CASE
        WHEN ps.avg_fragmentation_in_percent > 30 THEN
            'ALTER INDEX ' + QUOTENAME(i.name) + ' ON ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
            + ' REBUILD WITH (ONLINE = ON, RESUMABLE = ON, SORT_IN_TEMPDB = ON);'
        WHEN ps.avg_fragmentation_in_percent >= 5 THEN
            'ALTER INDEX ' + QUOTENAME(i.name) + ' ON ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
            + ' REORGANIZE;'
    END AS alter_statement
FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN    sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
JOIN    sys.tables  t ON t.object_id = i.object_id
JOIN    sys.schemas s ON s.schema_id = t.schema_id
WHERE   i.index_id > 0
  AND   i.name IS NOT NULL
  AND   ps.page_count >= @min_page_count
  AND   ps.avg_fragmentation_in_percent >= 5
ORDER BY ps.avg_fragmentation_in_percent DESC;
GO

-- Fill factor audit across ONLINE writable databases, generate-and-print only.
-- Finds non-default fill factors (not in 0,100) and emits resets to FILLFACTOR = 100.
-- Skips read-only, restoring, and secondary replicas. Review the fix_me column, then run it.
DECLARE @DatabaseName sysname;
DECLARE @sql nvarchar(max);

DECLARE database_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT d.name
    FROM   sys.databases d
    WHERE  d.state_desc = 'ONLINE'
      AND  d.is_read_only = 0
      AND  d.database_id > 4                          -- skip system databases
      AND  ISNULL(DATABASEPROPERTYEX(d.name, 'Updateability'), 'READ_WRITE') = 'READ_WRITE'
      AND  ISNULL(sys.fn_hadr_is_primary_replica(d.name), 1) = 1;   -- skip secondary replicas

OPEN database_cursor;
FETCH NEXT FROM database_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        SELECT  ' + QUOTENAME(@DatabaseName, '''') + N' AS database_name,
                ss.name + ''.'' + so.name AS table_name,
                si.name  AS index_name,
                si.type_desc AS index_type,
                si.fill_factor,
                ''ALTER INDEX '' + QUOTENAME(si.name)
                    + '' ON '' + QUOTENAME(ss.name) + ''.'' + QUOTENAME(so.name)
                    + '' REBUILD WITH (FILLFACTOR = 100, ONLINE = ON, RESUMABLE = ON);'' AS fix_me
        FROM    ' + QUOTENAME(@DatabaseName) + N'.sys.indexes si
        JOIN    ' + QUOTENAME(@DatabaseName) + N'.sys.objects so ON so.object_id = si.object_id
        JOIN    ' + QUOTENAME(@DatabaseName) + N'.sys.schemas ss ON ss.schema_id = so.schema_id
        WHERE   si.name IS NOT NULL
          AND   si.fill_factor NOT IN (0, 100)
          AND   so.type = ''U''
        ORDER BY si.fill_factor DESC;';

    -- PRINT @sql;   -- uncomment to inspect the generated batch
    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM database_cursor INTO @DatabaseName;
END

CLOSE database_cursor;
DEALLOCATE database_cursor;
GO
