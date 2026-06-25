/*
    Storage / Transaction log and VLFs
    Transaction log size and VLF analysis using sys.dm_db_log_info.
*/

-- VLF count plus used/unused per database, with used density.
-- First check for log fragmentation. High counts slow recovery, log backups and restores.
SELECT
    DB_NAME(li.database_id)                                      AS database_name,
    COUNT(*)                                                     AS total_vlfs,
    SUM(CASE WHEN li.vlf_active = 1 THEN 1 ELSE 0 END)           AS used_vlfs,
    SUM(CASE WHEN li.vlf_active = 0 THEN 1 ELSE 0 END)           AS unused_vlfs,
    CAST(100.0 * SUM(CASE WHEN li.vlf_active = 1 THEN 1 ELSE 0 END)
        / COUNT(*) AS decimal(5, 2))                             AS used_pct,
    CAST(AVG(li.vlf_size_mb) AS decimal(20, 2))                  AS avg_vlf_size_mb
FROM sys.databases d
CROSS APPLY sys.dm_db_log_info(d.database_id) li
WHERE d.state_desc = 'ONLINE'
GROUP BY li.database_id
ORDER BY total_vlfs DESC;
GO

-- Same as above but only databases over the VLF threshold.
-- Use this as the alerting query - these are the logs to shrink and regrow.
DECLARE @VlfThreshold int = 1000;

SELECT
    DB_NAME(li.database_id)                                      AS database_name,
    COUNT(*)                                                     AS total_vlfs,
    SUM(CASE WHEN li.vlf_active = 1 THEN 1 ELSE 0 END)           AS used_vlfs,
    SUM(CASE WHEN li.vlf_active = 0 THEN 1 ELSE 0 END)           AS unused_vlfs
FROM sys.databases d
CROSS APPLY sys.dm_db_log_info(d.database_id) li
WHERE d.state_desc = 'ONLINE'
GROUP BY li.database_id
HAVING COUNT(*) > @VlfThreshold
ORDER BY total_vlfs DESC;
GO

-- Log space usage per online database (size and percent used).
-- Catches logs that are full or near full before they block writes.
-- sys.dm_db_log_space_usage returns only the current database, so loop with a cursor.
DECLARE @results table (
    database_name        sysname,
    total_log_mb         decimal(20, 2),
    used_log_mb          decimal(20, 2),
    used_log_pct         decimal(5, 2)
);
DECLARE @db sysname;
DECLARE @sql nvarchar(max);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE state_desc = 'ONLINE';

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db) + N';
        SELECT
            DB_NAME(database_id),
            CAST(total_log_size_in_bytes / 1048576.0 AS decimal(20, 2)),
            CAST(used_log_space_in_bytes / 1048576.0 AS decimal(20, 2)),
            CAST(used_log_space_in_percent AS decimal(5, 2))
        FROM sys.dm_db_log_space_usage;';
    INSERT INTO @results
    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM db_cur INTO @db;
END
CLOSE db_cur;
DEALLOCATE db_cur;

SELECT database_name, total_log_mb, used_log_mb, used_log_pct
FROM @results
ORDER BY used_log_pct DESC;
GO

-- VLF size distribution for one database.
-- Many small VLFs from tiny autogrowths is the usual cause of bloat.
-- Set context with USE first, dm_db_log_info reads the current database by default.
USE [YourDatabase];
GO

SELECT
    CAST(li.vlf_size_mb AS decimal(20, 2))  AS vlf_size_mb,
    COUNT(*)                                AS vlf_count,
    SUM(CASE WHEN li.vlf_active = 1 THEN 1 ELSE 0 END) AS used_vlfs
FROM sys.dm_db_log_info(DB_ID()) li
GROUP BY li.vlf_size_mb
ORDER BY vlf_count DESC;
GO

-- Log resize advisory for one database, derived from the current log size.
-- After shrinking a bloated log, regrow it in this many even steps to keep VLFs sane.
-- Target rounds the current size up to the next GB (min 512 MB); grow in 8 GB chunks (4 VLFs each)
-- so each chunk yields 16 MB VLFs and the final layout stays small. No DBCC LOGINFO.
USE [YourDatabase];
GO

DECLARE @current_log_mb decimal(20, 2) = (
    SELECT SUM(size) * 8 / 1024.0
    FROM sys.master_files
    WHERE database_id = DB_ID() AND type_desc = 'LOG'
);
DECLARE @current_vlfs int = (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID()));

-- Round up to the next whole GB, floor at 512 MB.
DECLARE @target_mb int = CASE
    WHEN @current_log_mb <= 512 THEN 512
    ELSE CAST(CEILING(@current_log_mb / 1024.0) AS int) * 1024
END;
-- Initial size and autogrow increment, both capped at 8 GB to avoid oversized VLFs.
DECLARE @growth_mb int = CASE WHEN @target_mb < 8192 THEN @target_mb ELSE 8192 END;
DECLARE @initial_mb int = @growth_mb;

SELECT
    DB_NAME(DB_ID())                                            AS database_name,
    CAST(@current_log_mb AS decimal(20, 2))                     AS current_log_mb,
    @current_vlfs                                               AS current_vlfs,
    @target_mb                                                  AS recommended_target_mb,
    @initial_mb                                                 AS suggested_initial_mb,
    @growth_mb                                                  AS suggested_autogrow_mb,
    CEILING(@target_mb * 1.0 / @growth_mb)                      AS grow_iterations,
    -- Roughly 4 VLFs per chunk for chunks > 1 GB; this is the layout the regrow produces.
    CEILING(@target_mb * 1.0 / @growth_mb) * 4                  AS projected_vlfs;
GO
