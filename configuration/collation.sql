/*
    Configuration / Collation
    Server, database, and column collation audit and change.
*/

-- Server, database default, and tempdb collation at a glance.
-- First check when chasing collation conflicts (tempdb joins, #temp tables).
SELECT
    SERVERPROPERTY('Collation')                         AS server_collation,
    DATABASEPROPERTYEX(DB_NAME(), 'Collation')          AS current_db_collation,
    CONVERT(sysname, DATABASEPROPERTYEX('tempdb', 'Collation')) AS tempdb_collation;
GO

-- Database default collation for every database.
-- Spot databases that drift from the instance/server collation.
SELECT
    name AS database_name,
    collation_name,
    CASE WHEN collation_name = CONVERT(sysname, SERVERPROPERTY('Collation'))
         THEN 0 ELSE 1 END AS differs_from_server
FROM sys.databases
ORDER BY differs_from_server DESC, name;
GO

-- Column-level collations for tables and user-defined table types in the current database.
-- Baseline audit of every collated column.
USE [YourDatabase];
GO
SELECT
    'Table' AS object_type,
    s.name  AS schema_name,
    t.name  AS object_name,
    c.name  AS column_name,
    ty.name AS data_type,
    c.collation_name AS collation
FROM sys.tables t
    INNER JOIN sys.schemas s  ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c  ON t.object_id = c.object_id
    INNER JOIN sys.types ty   ON c.user_type_id = ty.user_type_id
WHERE c.collation_name IS NOT NULL
UNION ALL
SELECT
    'User-Defined Table Type' AS object_type,
    SCHEMA_NAME(tt.schema_id) AS schema_name,
    tt.name AS object_name,
    c.name  AS column_name,
    TYPE_NAME(c.user_type_id) AS data_type,
    c.collation_name AS collation
FROM sys.table_types tt
    INNER JOIN sys.columns c ON c.object_id = tt.type_table_object_id
WHERE c.collation_name IS NOT NULL
ORDER BY object_type, schema_name, object_name, column_name;
GO

-- Columns whose collation differs from the database default.
-- The usual cause of "cannot resolve collation conflict" errors.
USE [YourDatabase];
GO
SELECT
    s.name  AS schema_name,
    t.name  AS table_name,
    c.name  AS column_name,
    ty.name AS data_type,
    c.collation_name AS column_collation,
    DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS database_collation
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    INNER JOIN sys.types ty  ON c.user_type_id = ty.user_type_id
WHERE c.collation_name IS NOT NULL
  AND c.collation_name <> CONVERT(sysname, DATABASEPROPERTYEX(DB_NAME(), 'Collation'))
  AND t.type = 'U'
  AND ty.is_user_defined <> 1
ORDER BY s.name, t.name, c.name;
GO

-- Columns that already use a specific collation.
-- Set @TargetCollation to the one you are looking for.
-- SQL Server 2025 adds UTF-8 collations (suffix _UTF8) for native UTF-8 storage in char/varchar.
USE [YourDatabase];
GO
DECLARE @TargetCollation sysname = N'Latin1_General_BIN';
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME()    AS database_name,
    s.name  AS schema_name,
    t.name  AS table_name,
    c.name  AS column_name,
    ty.name AS data_type,
    c.collation_name AS collation
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    INNER JOIN sys.types ty  ON c.user_type_id = ty.user_type_id
WHERE c.collation_name = @TargetCollation
  AND t.type = 'U'
  AND ty.is_user_defined <> 1
ORDER BY s.name, t.name, c.name;
GO

-- Instance-wide rollup: database default collation plus a count of column/table-type
-- collations per database. Iterates ONLINE databases with a cursor (replaces sp_MSforeachdb).
-- Wide audit across the whole server.
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#collation_stats') IS NOT NULL DROP TABLE #collation_stats;
CREATE TABLE #collation_stats (
    server_name      sysname,
    database_name    sysname,
    source_type      nvarchar(50),
    collation        sysname NULL,
    collation_count  int
);

INSERT INTO #collation_stats (server_name, database_name, source_type, collation, collation_count)
SELECT @@SERVERNAME, name, 'Database', collation_name, NULL
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND name NOT IN ('tempdb','msdb','ssisdb');

DECLARE @db sysname, @sql nvarchar(max);
DECLARE col_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND name NOT IN ('tempdb','msdb','ssisdb');

OPEN col_cur;
FETCH NEXT FROM col_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';
        INSERT INTO #collation_stats (server_name, database_name, source_type, collation, collation_count)
        SELECT @@SERVERNAME, DB_NAME(), ''Columns'', c.collation_name, COUNT(*)
        FROM sys.tables t
            INNER JOIN sys.columns c ON t.object_id = c.object_id
        WHERE t.type = ''U'' AND c.collation_name IS NOT NULL
        GROUP BY c.collation_name
        UNION ALL
        SELECT @@SERVERNAME, DB_NAME(), ''Table Types'', c.collation_name, COUNT(*)
        FROM sys.table_types tt
            INNER JOIN sys.columns c ON c.object_id = tt.type_table_object_id
        WHERE c.collation_name IS NOT NULL
        GROUP BY c.collation_name;';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM col_cur INTO @db;
END;

CLOSE col_cur;
DEALLOCATE col_cur;

SELECT server_name, database_name, source_type, collation, collation_count
FROM #collation_stats
ORDER BY server_name, database_name, source_type, collation;

DROP TABLE #collation_stats;
GO

-- Generate ALTER COLUMN statements to move columns off their current collation.
-- Prints the scripts only; review and run them yourself.
-- Set @TargetCollation to the collation you want.
USE [YourDatabase];
GO
DECLARE @TargetCollation sysname = N'Latin1_General_BIN';
SELECT
    s.name  AS schema_name,
    t.name  AS table_name,
    c.name  AS column_name,
    ty.name AS data_type,
    c.max_length AS data_max_length,
    c.collation_name AS current_collation,
    'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
        + ' ALTER COLUMN ' + QUOTENAME(c.name) + ' ' + ty.name
        + CASE
            WHEN c.max_length = -1 THEN '(MAX)'
            WHEN ty.name IN ('char','varchar','nchar','nvarchar')
                THEN '(' + CAST(c.max_length / (CASE WHEN ty.name IN ('nchar','nvarchar') THEN 2 ELSE 1 END) AS varchar(10)) + ')'
            ELSE ''
          END
        + ' COLLATE ' + @TargetCollation
        + CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END + ';' AS alter_script
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    INNER JOIN sys.types ty  ON c.user_type_id = ty.user_type_id
WHERE c.collation_name <> @TargetCollation
  AND t.type = 'U'
  AND ty.is_user_defined <> 1
ORDER BY s.name, t.name, c.name;
GO

-- DESTRUCTIVE: changes column collation in place. Rebuilds data, can fail on indexed,
-- computed, or constraint-bound columns, and rewrites the column.
-- Safe by default: generate-and-print only. Set @WhatIf = 0 to actually run the ALTERs.
USE [YourDatabase];
GO
SET NOCOUNT ON;
DECLARE @WhatIf bit = 1;
DECLARE @TargetCollation sysname = N'Latin1_General_BIN';

IF OBJECT_ID('tempdb..#alter_scripts') IS NOT NULL DROP TABLE #alter_scripts;
CREATE TABLE #alter_scripts (id int IDENTITY(1,1), alter_script nvarchar(max));

INSERT INTO #alter_scripts (alter_script)
SELECT
    'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
        + ' ALTER COLUMN ' + QUOTENAME(c.name) + ' ' + ty.name
        + CASE
            WHEN c.max_length = -1 THEN '(MAX)'
            WHEN ty.name IN ('char','varchar','nchar','nvarchar')
                THEN '(' + CAST(c.max_length / (CASE WHEN ty.name IN ('nchar','nvarchar') THEN 2 ELSE 1 END) AS varchar(10)) + ')'
            ELSE ''
          END
        + ' COLLATE ' + @TargetCollation
        + CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END + ';'
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    INNER JOIN sys.types ty  ON c.user_type_id = ty.user_type_id
WHERE c.collation_name <> @TargetCollation
  AND t.type = 'U'
  AND ty.is_user_defined <> 1
ORDER BY s.name, t.name, c.name;

DECLARE @id int = 1, @max int, @script nvarchar(max);
SELECT @max = MAX(id) FROM #alter_scripts;

WHILE @id <= @max
BEGIN
    SELECT @script = alter_script FROM #alter_scripts WHERE id = @id;
    IF @WhatIf = 1
        PRINT @script;
    ELSE
        BEGIN TRY
            EXEC sys.sp_executesql @script;
            PRINT 'OK: ' + @script;
        END TRY
        BEGIN CATCH
            PRINT 'Error in: ' + @script;
            PRINT 'Error: ' + ERROR_MESSAGE();
        END CATCH
    SET @id = @id + 1;
END;

DROP TABLE #alter_scripts;
GO

-- DESTRUCTIVE: changes the database default collation. Takes the database SINGLE_USER
-- (kicks all connections), only affects new objects/columns, and fails if any user table
-- has collation-dependent dependencies. Set @WhatIf = 0 and uncomment the batch to run it.
DECLARE @WhatIf bit = 1;
DECLARE @DatabaseName sysname = N'YourDatabase';
DECLARE @TargetCollation sysname = N'Latin1_General_BIN';
IF @WhatIf = 1
    PRINT 'WhatIf: would set ' + QUOTENAME(@DatabaseName) + ' COLLATE ' + @TargetCollation;
GO
-- ALTER DATABASE [YourDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
-- GO
-- ALTER DATABASE [YourDatabase] COLLATE Latin1_General_BIN;
-- GO
-- ALTER DATABASE [YourDatabase] SET MULTI_USER;
-- GO
