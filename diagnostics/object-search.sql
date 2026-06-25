/*
    Diagnostics / Object search
    Search objects, columns, and module text across databases.
*/

-- Find an object by name in the current database.
-- Quick lookup for a proc/view/function/table/trigger; returns its definition.
USE [YourDatabase];
GO

DECLARE @SearchTerm sysname = N'%fnMyFunction%';

SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS ObjectName,
    o.type_desc AS ObjectType,
    o.create_date AS CreationDate,
    o.modify_date AS ModificationDate,
    m.definition AS ObjectDefinition
FROM sys.objects o
    LEFT JOIN sys.sql_modules m ON o.object_id = m.object_id
WHERE o.name LIKE @SearchTerm
    AND o.type IN ('FN', 'IF', 'TF', 'P', 'V', 'U', 'TR')
ORDER BY o.name;
GO

-- Find a column by name in the current database.
-- Useful when tracking down where a column lives across tables.
USE [YourDatabase];
GO

DECLARE @ColumnName sysname = N'MyColumn';
DECLARE @TableName sysname = N'%';   -- narrow with a pattern, or leave as % for all tables

SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    c.name AS ColumnName,
    TYPE_NAME(c.user_type_id) AS DataType
FROM sys.tables t
    INNER JOIN sys.columns c ON c.object_id = t.object_id
WHERE c.name = @ColumnName
    AND t.name LIKE @TableName
ORDER BY SchemaName, TableName;
GO

-- Find a column by name across every online database.
-- Cursors over ONLINE databases; useful when the table/db is unknown.
DECLARE @ColumnName sysname = N'MyColumn';
DECLARE @DatabaseName sysname;
DECLARE @sql nvarchar(max);

IF OBJECT_ID('tempdb..#ColumnHits') IS NOT NULL DROP TABLE #ColumnHits;
CREATE TABLE #ColumnHits (
    DatabaseName sysname,
    SchemaName sysname,
    TableName sysname,
    ColumnName sysname,
    DataType sysname
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        USE ' + QUOTENAME(@DatabaseName) + N';
        SELECT
            DB_NAME() AS DatabaseName,
            SCHEMA_NAME(t.schema_id) AS SchemaName,
            t.name AS TableName,
            c.name AS ColumnName,
            TYPE_NAME(c.user_type_id) AS DataType
        FROM sys.tables t
            INNER JOIN sys.columns c ON c.object_id = t.object_id
        WHERE c.name LIKE @ColumnName;';

    INSERT INTO #ColumnHits (DatabaseName, SchemaName, TableName, ColumnName, DataType)
    EXEC sys.sp_executesql @sql, N'@ColumnName sysname', @ColumnName = @ColumnName;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT DatabaseName, SchemaName, TableName, ColumnName, DataType
FROM #ColumnHits
ORDER BY DatabaseName, SchemaName, TableName, ColumnName;

DROP TABLE #ColumnHits;
GO

-- Search every online database for objects matching a name pattern.
-- Cursors over ONLINE databases and runs a parameterized search in each.
-- Covers schema-scoped objects, CLR assemblies, and XML schema collections.
DECLARE @SearchTerm nvarchar(128) = N'%Person%';
DECLARE @DatabaseName sysname;
DECLARE @sql nvarchar(max);

IF OBJECT_ID('tempdb..#ObjectHits') IS NOT NULL DROP TABLE #ObjectHits;
CREATE TABLE #ObjectHits (
    DatabaseName sysname,
    SchemaName sysname NULL,
    ObjectName sysname,
    ObjectType nvarchar(60),
    AssemblyName sysname NULL
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        USE ' + QUOTENAME(@DatabaseName) + N';
        SELECT
            DB_NAME() AS DatabaseName,
            SCHEMA_NAME(o.schema_id) AS SchemaName,
            o.name AS ObjectName,
            o.type_desc AS ObjectType,
            a.name AS AssemblyName
        FROM sys.objects o
            LEFT JOIN sys.assembly_modules m ON o.object_id = m.object_id
            LEFT JOIN sys.assemblies a ON m.assembly_id = a.assembly_id
        WHERE o.name LIKE @SearchTerm
        UNION ALL
        SELECT DB_NAME(), NULL, a.name, N''ASSEMBLY'', NULL
        FROM sys.assemblies a
        WHERE a.name LIKE @SearchTerm
        UNION ALL
        SELECT DB_NAME(), SCHEMA_NAME(x.schema_id), x.name, N''XML_SCHEMA_COLLECTION'', NULL
        FROM sys.xml_schema_collections x
        WHERE x.name LIKE @SearchTerm;';

    INSERT INTO #ObjectHits (DatabaseName, SchemaName, ObjectName, ObjectType, AssemblyName)
    EXEC sys.sp_executesql @sql, N'@SearchTerm nvarchar(128)', @SearchTerm = @SearchTerm;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT DatabaseName, SchemaName, ObjectName, ObjectType, AssemblyName
FROM #ObjectHits
ORDER BY DatabaseName, ObjectType, SchemaName, ObjectName;

DROP TABLE #ObjectHits;
GO

-- Search module definitions in every online database for a string.
-- Finds where a table, column, or literal is referenced in proc/view/function/trigger text.
-- sys.sql_modules holds the full definition (no OBJECT_DEFINITION truncation).
DECLARE @SearchTerm nvarchar(128) = N'%Report_PaymentDetail%';
DECLARE @DatabaseName sysname;
DECLARE @sql nvarchar(max);

IF OBJECT_ID('tempdb..#ModuleHits') IS NOT NULL DROP TABLE #ModuleHits;
CREATE TABLE #ModuleHits (
    DatabaseName sysname,
    SchemaName sysname,
    ObjectName sysname,
    ObjectType nvarchar(60),
    Definition nvarchar(max)
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        USE ' + QUOTENAME(@DatabaseName) + N';
        SELECT
            DB_NAME() AS DatabaseName,
            SCHEMA_NAME(o.schema_id) AS SchemaName,
            o.name AS ObjectName,
            o.type_desc AS ObjectType,
            m.definition AS Definition
        FROM sys.sql_modules m
            INNER JOIN sys.objects o ON o.object_id = m.object_id
        WHERE m.definition LIKE @SearchTerm;';

    INSERT INTO #ModuleHits (DatabaseName, SchemaName, ObjectName, ObjectType, Definition)
    EXEC sys.sp_executesql @sql, N'@SearchTerm nvarchar(128)', @SearchTerm = @SearchTerm;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT DatabaseName, SchemaName, ObjectName, ObjectType, Definition
FROM #ModuleHits
ORDER BY DatabaseName, ObjectType, SchemaName, ObjectName;

DROP TABLE #ModuleHits;
GO
