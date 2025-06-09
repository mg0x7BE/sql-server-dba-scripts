
/**********************************************************************************************/
-- Check database-level and column-level collation for the entire instance

IF OBJECT_ID('tempdb..#CollationStats') IS NOT NULL
    DROP TABLE #CollationStats;

CREATE TABLE #CollationStats (
                                 ServerName NVARCHAR(128),
                                 DatabaseName NVARCHAR(128),
                                 Collation NVARCHAR(128),
                                 CollationCount INT,
                                 SourceType NVARCHAR(50)
);
INSERT INTO #CollationStats (ServerName, DatabaseName, Collation, CollationCount, SourceType)
SELECT
    @@SERVERNAME AS ServerName,
    d.name AS DatabaseName,
    d.collation_name AS Collation,
            0 AS CollationCount,
            'Database' AS SourceType
FROM sys.databases d
WHERE d.name not in ('tempdb','msdb')
GROUP BY d.name, d.collation_name;

DECLARE @SQL NVARCHAR(MAX) = '';
SELECT @SQL = @SQL +
              'USE [' + name + ']; ' +
              'INSERT INTO #CollationStats (ServerName, DatabaseName, Collation, CollationCount, SourceType) ' +
              'SELECT ' +
              '@@SERVERNAME AS ServerName, ' +
              '''' + name + ''' AS DatabaseName, ' +
              'c.collation_name AS Collation, ' +
              'COUNT(*) AS CollationCount, ' +
              '''Columns'' AS SourceType ' +
              'FROM sys.tables t ' +
              'INNER JOIN sys.schemas s ON t.schema_id = s.schema_id ' +
              'INNER JOIN sys.columns c ON t.object_id = c.object_id ' +
              'WHERE t.type = ''U'' ' +
              'AND c.collation_name IS NOT NULL ' +
              'GROUP BY c.collation_name; '
FROM sys.databases
WHERE state = 0 and name not in ('tempdb','msdb');

EXEC sp_executesql @SQL;

SELECT
    ServerName,
    DatabaseName,
    SourceType,
    CASE WHEN (SourceType = 'Database') THEN 'Database' ELSE CONVERT(nvarchar(255), CollationCount) END as CollationCount,
    Collation
FROM #CollationStats
ORDER BY 1,2,3 desc,5
DROP TABLE #CollationStats;

/**********************************************************************************************/
-- Column-level collation details
use my_database;

SELECT
    @@SERVERNAME AS ServerName,
    db_name() as DatabaseName,
    s.name AS SchemaName,
    t.name AS TableName,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.collation_name AS Collation
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE c.collation_name = 'Latin1_General_BIN'
  AND t.type = 'U' -- User Table
  AND ty.is_user_defined <> 1
ORDER BY 1,2,3,4,5

/**********************************************************************************************/
-- Change database collation

ALTER DATABASE my_database SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

ALTER DATABASE my_database
    COLLATE Latin1_General_BIN;
GO

ALTER DATABASE my_database SET MULTI_USER;
GO

/**********************************************************************************************/
-- Change collation on column-level

use my_database;

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length AS DataMaxLength,
    c.collation_name AS Collation,
    'ALTER TABLE [' + s.name + '].[' + t.name + '] ALTER COLUMN [' + c.name + '] ' +
    ty.name +
    CASE
        WHEN c.max_length = -1 THEN '(MAX)'
        WHEN ty.name IN ('char', 'varchar', 'nchar', 'nvarchar') THEN '(' + CAST(c.max_length / (CASE WHEN ty.name IN ('nchar', 'nvarchar') THEN 2 ELSE 1 END) AS VARCHAR(10)) + ')'
        ELSE ''
        END +
    ' COLLATE Latin1_General_BIN ' + CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END AS AlterScript

FROM sys.tables t
         INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
         INNER JOIN sys.columns c ON t.object_id = c.object_id
         INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE c.collation_name <> 'Latin1_General_BIN'
  AND t.type = 'U' -- User Table
  AND ty.is_user_defined <> 1
ORDER BY 1,2,3

/**********************************************************************************************/
-- Find object

SELECT
    o.name AS ObjectName,
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.type_desc AS ObjectType,
    o.create_date AS CreationDate,
    o.modify_date AS ModificationDate,
    m.definition AS ObjectDefinition
FROM
    sys.objects o
LEFT JOIN
    sys.sql_modules m ON o.object_id = m.object_id
WHERE
    o.name LIKE '%fnMyFunction%'
  AND o.type IN ('FN', 'IF', 'TF', 'P', 'V', 'U', 'TR')
ORDER BY
    o.name;

/**********************************************************************************************/
-- Find column

SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME = 'MyColumn'
  AND TABLE_NAME LIKE '%MyTable%';

/**********************************************************************************************/
-- Change collation on column-level (uncomment sp_executesql section)

use my_database

IF OBJECT_ID('tempdb..#AlterScripts') IS NOT NULL
    DROP TABLE #AlterScripts;

CREATE TABLE #AlterScripts (
                               ID INT IDENTITY(1,1),
                               AlterScript NVARCHAR(MAX)
);

INSERT INTO #AlterScripts (AlterScript)
SELECT
    'ALTER TABLE [' + s.name + '].[' + t.name + '] ALTER COLUMN [' + c.name + '] ' +
    ty.name +
    CASE
        WHEN c.max_length = -1 THEN '(MAX)'
        WHEN ty.name IN ('char', 'varchar', 'nchar', 'nvarchar') THEN '(' + CAST(c.max_length / (CASE WHEN ty.name IN ('nchar', 'nvarchar') THEN 2 ELSE 1 END) AS VARCHAR(10)) + ')'
        ELSE ''
        END +
    ' COLLATE Latin1_General_BIN ' +
    CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END AS AlterScript
FROM sys.tables t
         INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
         INNER JOIN sys.columns c ON t.object_id = c.object_id
         INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE c.collation_name <> 'Latin1_General_BIN'
  AND t.type = 'U' -- User Table
  AND ty.is_user_defined <> 1
ORDER BY s.name, t.name, c.name;


DECLARE @CurrentScript NVARCHAR(MAX);
DECLARE @CurrentID INT;
DECLARE @MaxID INT;


SELECT @MaxID = MAX(ID) FROM #AlterScripts;
SET @CurrentID = 1;

WHILE @CurrentID <= @MaxID
    BEGIN

        SELECT @CurrentScript = AlterScript
        FROM #AlterScripts
        WHERE ID = @CurrentID;

        BEGIN TRY
            -- EXEC sp_executesql @CurrentScript;
            -- PRINT 'OK: ' + @CurrentScript;
        END TRY
        BEGIN CATCH
            PRINT 'Error in: ' + @CurrentScript;
            PRINT 'Error: ' + ERROR_MESSAGE();
        END CATCH

        SET @CurrentID = @CurrentID + 1;
    END;

DROP TABLE #AlterScripts;