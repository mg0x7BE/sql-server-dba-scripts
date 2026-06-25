/*
    Programmability / Constraints
    Inspect and re-trust untrusted foreign key and CHECK constraints.
*/

-- List all constraints in the current database.
-- Quick inventory of FK, CHECK, DEFAULT, PRIMARY KEY, UNIQUE objects.
USE [YourDatabase];
GO
SELECT OBJECT_NAME(object_id) AS ConstraintName,
       SCHEMA_NAME(schema_id) AS SchemaName,
       OBJECT_NAME(parent_object_id) AS TableName,
       type_desc AS ConstraintType
FROM sys.objects
WHERE type_desc LIKE '%CONSTRAINT'
ORDER BY SchemaName, TableName, ConstraintName;
GO

-- Untrusted CHECK constraints in the current database.
-- is_not_trusted = 1 means the optimizer cannot rely on it and skips related plan simplifications.
SELECT SCHEMA_NAME(t.schema_id) AS SchemaName,
       OBJECT_NAME(cc.parent_object_id) AS TableName,
       cc.name AS ConstraintName,
       cc.is_not_trusted,
       cc.is_disabled
FROM sys.check_constraints cc
JOIN sys.tables t ON cc.parent_object_id = t.object_id
WHERE cc.is_not_trusted = 1
ORDER BY SchemaName, TableName, ConstraintName;
GO

-- Untrusted foreign keys in the current database.
-- Same idea as CHECK constraints: untrusted FKs hurt plan quality and join elimination.
SELECT SCHEMA_NAME(t.schema_id) AS SchemaName,
       OBJECT_NAME(fk.parent_object_id) AS TableName,
       fk.name AS ConstraintName,
       fk.is_not_trusted,
       fk.is_disabled
FROM sys.foreign_keys fk
JOIN sys.tables t ON fk.parent_object_id = t.object_id
WHERE fk.is_not_trusted = 1
ORDER BY SchemaName, TableName, ConstraintName;
GO

-- Re-trust one constraint.
-- NOCHECK leaves data unvalidated and the constraint untrusted; WITH CHECK CHECK re-validates
-- existing rows and restores trust. Plain CHECK CONSTRAINT re-enables WITHOUT validating, so it
-- stays untrusted - use WITH CHECK CHECK.
-- ALTER TABLE dbo.YourTable WITH CHECK CHECK CONSTRAINT YourConstraint;
GO

-- Find and re-trust all untrusted FKs and CHECK constraints across writable databases.
-- Skips disabled and not-for-replication constraints. Generate-and-print by default; set
-- @PrintOnly = 0 to execute the generated ALTER TABLE statements (re-validates data, can be slow
-- and takes schema-modify locks).
SET NOCOUNT ON;

DECLARE @PrintOnly bit = 1;

DECLARE @DatabaseName sysname;
DECLARE @SQL nvarchar(max);

CREATE TABLE #ConstraintsToFix (
    DatabaseName sysname,
    SchemaName sysname,
    TableName sysname,
    ConstraintName sysname
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
    AND DATABASEPROPERTYEX(name, 'Updateability') = 'READ_WRITE'
    AND is_read_only = 0
    AND name NOT IN ('master', 'tempdb', 'model', 'msdb');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'
    INSERT INTO #ConstraintsToFix (DatabaseName, SchemaName, TableName, ConstraintName)
    SELECT ' + QUOTENAME(@DatabaseName, '''') + N', s.name, o.name, i.name
    FROM ' + QUOTENAME(@DatabaseName) + N'.sys.foreign_keys i
    JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.objects o ON i.parent_object_id = o.object_id
    JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas s ON o.schema_id = s.schema_id
    WHERE i.is_not_trusted = 1 AND i.is_not_for_replication = 0 AND i.is_disabled = 0
    UNION
    SELECT ' + QUOTENAME(@DatabaseName, '''') + N', s.name, o.name, i.name
    FROM ' + QUOTENAME(@DatabaseName) + N'.sys.check_constraints i
    JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.objects o ON i.parent_object_id = o.object_id
    JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas s ON o.schema_id = s.schema_id
    WHERE i.is_not_trusted = 1 AND i.is_not_for_replication = 0 AND i.is_disabled = 0;';

    EXEC sys.sp_executesql @SQL;
    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

DECLARE @DBName sysname, @SchemaName sysname, @TableName sysname, @ConstraintName sysname;

DECLARE constraint_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT DatabaseName, SchemaName, TableName, ConstraintName
FROM #ConstraintsToFix;

OPEN constraint_cursor;
FETCH NEXT FROM constraint_cursor INTO @DBName, @SchemaName, @TableName, @ConstraintName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'USE ' + QUOTENAME(@DBName) + N';
    ALTER TABLE ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName) + N'
    WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(@ConstraintName) + N';';

    PRINT CHAR(13) + CHAR(10);
    PRINT @SQL;

    -- Destructive when @PrintOnly = 0: executes ALTER TABLE which re-validates data and locks the table.
    IF @PrintOnly = 0
    BEGIN TRY
        EXEC sys.sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        PRINT 'Error on ' + QUOTENAME(@ConstraintName) +
              ' in ' + QUOTENAME(@DBName) + '.' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) +
              ': ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM constraint_cursor INTO @DBName, @SchemaName, @TableName, @ConstraintName;
END;

CLOSE constraint_cursor;
DEALLOCATE constraint_cursor;
DROP TABLE #ConstraintsToFix;
GO
