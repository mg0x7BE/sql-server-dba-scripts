/*
    Storage / Database files
    Database file layout, size, growth, and free space.
*/

-- File layout for the current database: logical name, type, path.
-- Quick orientation before anything else.
USE [YourDatabase];
GO
SELECT
    file_id,
    name,
    type_desc,
    physical_name,
    state_desc,
    CAST(size * 8.0 / 1024 AS decimal(18,2)) AS allocated_mb
FROM sys.database_files
ORDER BY type_desc, file_id;
GO

-- Files ordered like the SSMS GUI (data file first, then by name) for one database.
-- Set the target database below.
DECLARE @DatabaseName sysname = N'YourDatabase';
SELECT
    DB_NAME(database_id) AS database_name,
    file_id,
    type_desc,
    data_space_id,
    name,
    physical_name
FROM sys.master_files
WHERE database_id = DB_ID(@DatabaseName)
ORDER BY type, CASE WHEN file_id = 1 THEN 0 ELSE 1 END, name;
GO

-- Used vs free space per file for the current database.
-- FILEPROPERTY runs in the current DB context, so USE the database first.
USE [YourDatabase];
GO
SELECT
    df.file_id,
    df.name,
    df.physical_name,
    CAST(df.size * 8.0 / 1024 AS decimal(18,2)) AS file_size_mb,
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') * 8.0 / 1024 AS decimal(18,2)) AS space_used_mb,
    CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) * 8.0 / 1024 AS decimal(18,2)) AS free_space_mb,
    CAST(100.0 * FILEPROPERTY(df.name, 'SpaceUsed') / NULLIF(df.size, 0) AS decimal(5,2)) AS percent_used
FROM sys.database_files df
ORDER BY free_space_mb;
GO

-- File growth and max-size settings for every database.
-- System databases first. Flag is_percent_growth - percent growth is usually a mistake.
SELECT
    DB_NAME(database_id) AS database_name,
    type_desc,
    CASE
        WHEN is_percent_growth = 1 THEN CAST(growth AS varchar(10)) + '%'
        ELSE CAST(CAST(growth AS bigint) * 8 / 1024 AS varchar(20)) + ' MB'
    END AS growth,
    CASE
        WHEN max_size = -1 THEN 'Unlimited'
        WHEN max_size = 0 THEN 'No growth'
        ELSE CAST(CAST(max_size AS bigint) * 8 / 1024 AS varchar(20)) + ' MB'
    END AS max_size,
    is_percent_growth
FROM sys.master_files
ORDER BY
    CASE WHEN database_id IN (1,2,3,4) THEN 0 ELSE 1 END,
    DB_NAME(database_id),
    type_desc;
GO

-- Size of every user database (data + log), largest first.
SELECT
    DB_NAME(mf.database_id) AS database_name,
    CAST(SUM(mf.size) * 8.0 / 1024 AS decimal(18,2)) AS size_mb
FROM sys.master_files mf
JOIN sys.databases d ON d.database_id = mf.database_id
WHERE d.database_id > 4
GROUP BY DB_NAME(mf.database_id)
ORDER BY size_mb DESC;
GO

-- Biggest user databases on a specific drive.
-- Set the drive prefix below (for example 'H:').
DECLARE @DrivePrefix nvarchar(10) = N'H:';
SELECT
    DB_NAME(database_id) AS database_name,
    CAST(SUM(size) * 8.0 / 1024 AS decimal(18,2)) AS size_mb
FROM sys.master_files
WHERE physical_name LIKE @DrivePrefix + '%'
  AND DB_NAME(database_id) NOT IN ('master','model','msdb','tempdb')
GROUP BY DB_NAME(database_id)
ORDER BY size_mb DESC;
GO

-- Distinct volume/LUN roots used by the instance.
-- Rough view of which mount points hold database files.
SELECT DISTINCT SUBSTRING(physical_name, 1, CHARINDEX('\', physical_name, 4) - 1) AS volume_root
FROM sys.master_files
WHERE CHARINDEX('\', physical_name, 4) > 0;
GO

-- Volume free space behind each database file (sys.dm_os_volume_stats).
-- Use this to spot disks about to fill, not just files about to fill.
SELECT DISTINCT
    vs.volume_mount_point,
    vs.logical_volume_name,
    CAST(vs.total_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2)) AS total_gb,
    CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2)) AS available_gb,
    CAST(100.0 * vs.available_bytes / NULLIF(vs.total_bytes, 0) AS decimal(5,2)) AS available_pct
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY available_pct;
GO

-- Per-file used vs free space across all ONLINE databases.
-- FILEPROPERTY is database-scoped, so iterate with a cursor instead of sp_MSforeachdb.
-- Optional: set @PhysicalNameLike to filter to specific paths (NULL = all files).
SET NOCOUNT ON;
DECLARE @PhysicalNameLike nvarchar(260) = NULL;

IF OBJECT_ID('tempdb..#file_space') IS NOT NULL DROP TABLE #file_space;
CREATE TABLE #file_space (
    database_name  sysname,
    file_name      sysname,
    physical_name  nvarchar(260),
    type_desc      nvarchar(60),
    size_mb        decimal(18,2),
    used_mb        decimal(18,2),
    free_mb        decimal(18,2),
    percent_used   decimal(5,2)
);

DECLARE @db sysname, @sql nvarchar(max);
DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE state_desc = 'ONLINE';

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';
        INSERT INTO #file_space (database_name, file_name, physical_name, type_desc, size_mb, used_mb, free_mb, percent_used)
        SELECT
            DB_NAME(),
            name,
            physical_name,
            type_desc,
            CAST(size * 8.0 / 1024 AS decimal(18,2)),
            CAST(FILEPROPERTY(name, ''SpaceUsed'') * 8.0 / 1024 AS decimal(18,2)),
            CAST((size - FILEPROPERTY(name, ''SpaceUsed'')) * 8.0 / 1024 AS decimal(18,2)),
            CAST(100.0 * FILEPROPERTY(name, ''SpaceUsed'') / NULLIF(size, 0) AS decimal(5,2))
        FROM sys.database_files
        WHERE (@flt IS NULL OR physical_name LIKE @flt);';
    EXEC sys.sp_executesql @sql, N'@flt nvarchar(260)', @flt = @PhysicalNameLike;
    FETCH NEXT FROM db_cur INTO @db;
END;

CLOSE db_cur;
DEALLOCATE db_cur;

SELECT * FROM #file_space ORDER BY free_mb;

DROP TABLE #file_space;
GO

-- Server-wide rollup: data vs log size and used space per user database.
-- One row per database, largest first. Good for a capacity snapshot.
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#db_sizes') IS NOT NULL DROP TABLE #db_sizes;
CREATE TABLE #db_sizes (
    server_name   sysname,
    database_name sysname,
    file_type     nvarchar(60),
    allocated_mb  decimal(18,2),
    used_mb       decimal(18,2)
);

DECLARE @dbname sysname, @cmd nvarchar(max);
DECLARE size_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND name NOT IN ('master','model','tempdb','msdb');

OPEN size_cur;
FETCH NEXT FROM size_cur INTO @dbname;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @cmd = N'
        USE ' + QUOTENAME(@dbname) + N';
        INSERT INTO #db_sizes (server_name, database_name, file_type, allocated_mb, used_mb)
        SELECT
            @@SERVERNAME,
            DB_NAME(),
            type_desc,
            CAST(size * 8.0 / 1024 AS decimal(18,2)),
            CAST(CAST(FILEPROPERTY(name, ''SpaceUsed'') AS bigint) * 8.0 / 1024 AS decimal(18,2))
        FROM sys.database_files;';
    EXEC sys.sp_executesql @cmd;
    FETCH NEXT FROM size_cur INTO @dbname;
END;

CLOSE size_cur;
DEALLOCATE size_cur;

SELECT
    server_name,
    database_name,
    CAST(SUM(allocated_mb) / 1024 AS decimal(10,2)) AS database_size_gb,
    CAST(SUM(CASE WHEN file_type = 'ROWS' THEN allocated_mb ELSE 0 END) / 1024 AS decimal(10,2)) AS data_size_gb,
    CAST(SUM(CASE WHEN file_type = 'LOG'  THEN allocated_mb ELSE 0 END) / 1024 AS decimal(10,2)) AS log_size_gb,
    CAST(SUM(used_mb) / 1024 AS decimal(10,2)) AS used_space_gb,
    CAST(SUM(CASE WHEN file_type = 'ROWS' THEN used_mb ELSE 0 END) / 1024 AS decimal(10,2)) AS data_used_gb,
    CAST(SUM(CASE WHEN file_type = 'LOG'  THEN used_mb ELSE 0 END) / 1024 AS decimal(10,2)) AS log_used_gb,
    CAST(100.0 * SUM(used_mb) / NULLIF(SUM(allocated_mb), 0) AS decimal(5,2)) AS used_pct
FROM #db_sizes
GROUP BY server_name, database_name
ORDER BY database_size_gb DESC;

DROP TABLE #db_sizes;
GO

-- Biggest tables in the current database: rows and total/used/unused space.
-- One row per table from sys.dm_db_partition_stats, largest first. USE the database first.
USE [YourDatabase];
GO
SELECT
    SCHEMA_NAME(t.schema_id) + '.' + t.name AS table_name,
    SUM(CASE WHEN ps.index_id IN (0,1) THEN ps.row_count ELSE 0 END) AS row_count,
    CAST(SUM(ps.reserved_page_count) * 8.0 / 1024 AS decimal(18,2)) AS total_mb,
    CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS decimal(18,2)) AS used_mb,
    CAST(SUM(ps.reserved_page_count - ps.used_page_count) * 8.0 / 1024 AS decimal(18,2)) AS unused_mb
FROM sys.tables t
JOIN sys.dm_db_partition_stats ps ON ps.object_id = t.object_id
GROUP BY t.schema_id, t.name
ORDER BY total_mb DESC;
GO
