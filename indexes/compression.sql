/*
    Indexes / Compression
    Data compression audit and rebuild with ROW, PAGE, or columnstore.
*/

-- Compression state for every object/index/partition in the current database.
-- Run first to see what is already compressed and what is not.
USE [YourDatabase];
GO

SELECT
    SCHEMA_NAME(o.schema_id)                                AS schema_name,
    o.name                                                  AS table_name,
    i.name                                                  AS index_name,
    i.type_desc                                             AS index_type,
    p.partition_number,
    p.rows,
    p.data_compression,
    p.data_compression_desc
FROM sys.partitions p
JOIN sys.indexes i ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.objects o ON o.object_id = p.object_id
WHERE o.type = 'U'
ORDER BY schema_name, table_name, i.index_id, p.partition_number;
-- data_compression: 0 NONE, 1 ROW, 2 PAGE, 3 COLUMNSTORE, 4 COLUMNSTORE_ARCHIVE
GO

-- Only the objects/partitions that already have some compression applied.
-- Quick "what did we already compress" list.
SELECT
    SCHEMA_NAME(o.schema_id)        AS schema_name,
    o.name                          AS table_name,
    i.name                          AS index_name,
    p.partition_number,
    p.rows,
    p.data_compression_desc
FROM sys.partitions p
JOIN sys.indexes i ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.objects o ON o.object_id = p.object_id
WHERE p.data_compression <> 0
  AND o.type = 'U'
ORDER BY schema_name, table_name, i.index_id, p.partition_number;
GO

-- Estimate savings before rebuilding. Compares current size to a target setting.
-- Set @TargetCompression to NONE, ROW, PAGE, COLUMNSTORE, or COLUMNSTORE_ARCHIVE.
-- size_with_requested_setting < size_with_current_setting means it is worth doing.
DECLARE @SchemaName        sysname = N'dbo',
        @ObjectName        sysname = N'YourTable',
        @IndexId           int     = NULL,   -- NULL = all indexes, 1 = clustered, etc.
        @PartitionNumber   int     = NULL,   -- NULL = all partitions
        @TargetCompression varchar(20) = 'PAGE';

EXEC sys.sp_estimate_data_compression_savings
     @schema_name        = @SchemaName,
     @object_name        = @ObjectName,
     @index_id           = @IndexId,
     @partition_number   = @PartitionNumber,
     @data_compression   = @TargetCompression;
GO

/*
    Generate ALTER ... REBUILD statements to apply row/page compression across
    rowstore indexes. Prints scripts only - review and run them yourself.
    Set @TargetCompression and @MaxDop, then copy the output to a new window.
*/
SET NOCOUNT ON;

DECLARE @TargetCompression sysname = N'PAGE',   -- NONE, ROW, or PAGE
        @MaxDop            int     = 4;          -- 0 = use server default

DECLARE @sql nvarchar(max);

;WITH idx AS (
    SELECT
        i.name                          AS index_name,
        SCHEMA_NAME(o.schema_id)        AS schema_name,
        o.name                          AS table_name,
        p.partition_number,
        COUNT(*) OVER (PARTITION BY p.object_id, p.index_id) AS partition_count
    FROM sys.indexes i
    JOIN sys.objects o    ON o.object_id = i.object_id
    JOIN sys.partitions p ON p.object_id = i.object_id AND p.index_id = i.index_id
    WHERE o.type = 'U'
      AND i.name IS NOT NULL
      AND i.type IN (1, 2)              -- rowstore clustered/nonclustered only
)
SELECT @sql = STRING_AGG(CAST(
    'ALTER INDEX ' + QUOTENAME(index_name)
    + ' ON ' + QUOTENAME(schema_name) + '.' + QUOTENAME(table_name)
    + CASE WHEN partition_count > 1
           THEN ' REBUILD PARTITION = ' + CONVERT(varchar(11), partition_number)
           ELSE ' REBUILD' END
    + ' WITH (DATA_COMPRESSION = ' + @TargetCompression
    + CASE WHEN @MaxDop > 0 THEN ', MAXDOP = ' + CONVERT(varchar(11), @MaxDop) ELSE '' END
    + ');'
    AS nvarchar(max)), CHAR(13) + CHAR(10))
    WITHIN GROUP (ORDER BY schema_name, table_name, index_name, partition_number)
FROM idx;

PRINT @sql;
GO

/*
    Generate ALTER ... REBUILD statements for existing columnstore indexes to set
    COLUMNSTORE or COLUMNSTORE_ARCHIVE. Prints scripts only - review and run them
    yourself. Targets columnstore indexes only; rowstore-to-columnstore conversion
    needs CREATE INDEX, not a rebuild.
*/
SET NOCOUNT ON;

DECLARE @ColumnstoreCompression sysname = N'COLUMNSTORE',   -- COLUMNSTORE or COLUMNSTORE_ARCHIVE
        @MaxDop                 int     = 4;                 -- 0 = use server default

DECLARE @sql nvarchar(max);

;WITH cs AS (
    SELECT
        i.name                          AS index_name,
        SCHEMA_NAME(o.schema_id)        AS schema_name,
        o.name                          AS table_name,
        p.partition_number,
        COUNT(*) OVER (PARTITION BY p.object_id, p.index_id) AS partition_count
    FROM sys.indexes i
    JOIN sys.objects o    ON o.object_id = i.object_id
    JOIN sys.partitions p ON p.object_id = i.object_id AND p.index_id = i.index_id
    WHERE o.type = 'U'
      AND i.name IS NOT NULL
      AND i.type IN (5, 6)              -- 5 clustered columnstore, 6 nonclustered columnstore
)
SELECT @sql = STRING_AGG(CAST(
    'ALTER INDEX ' + QUOTENAME(index_name)
    + ' ON ' + QUOTENAME(schema_name) + '.' + QUOTENAME(table_name)
    + CASE WHEN partition_count > 1
           THEN ' REBUILD PARTITION = ' + CONVERT(varchar(11), partition_number)
           ELSE ' REBUILD' END
    + ' WITH (DATA_COMPRESSION = ' + @ColumnstoreCompression
    + CASE WHEN @MaxDop > 0 THEN ', MAXDOP = ' + CONVERT(varchar(11), @MaxDop) ELSE '' END
    + ');'
    AS nvarchar(max)), CHAR(13) + CHAR(10))
    WITHIN GROUP (ORDER BY schema_name, table_name, index_name, partition_number)
FROM cs;

PRINT @sql;
