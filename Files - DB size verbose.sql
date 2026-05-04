SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#db_sizes') IS NOT NULL DROP TABLE #db_sizes;
CREATE TABLE #db_sizes (
                           server_name       sysname,
                           database_name     sysname,
                           file_type         nvarchar(60),
                           allocated_mb      decimal(18,2),
                           used_mb           decimal(18,2)
);

EXEC sp_MSforeachdb N'
USE [?];
INSERT INTO #db_sizes (server_name, database_name, file_type, allocated_mb, used_mb)
SELECT
    @@SERVERNAME,
    DB_NAME(),
    type_desc,
    CAST(size     * 8.0 / 1024 AS decimal(18,2)),
    CAST(CAST(FILEPROPERTY(name, ''SpaceUsed'') AS bigint) * 8.0 / 1024 AS decimal(18,2))
FROM sys.database_files;
';

SELECT
    server_name,
    database_name,
    CAST(SUM(allocated_mb) / 1024 AS decimal(10,2)) AS database_size_gb,
    CAST(SUM(CASE WHEN file_type = 'ROWS' THEN allocated_mb ELSE 0 END) / 1024 AS decimal(10,2)) AS data_size_gb,
    CAST(SUM(CASE WHEN file_type = 'LOG'  THEN allocated_mb ELSE 0 END) / 1024 AS decimal(10,2)) AS log_size_gb,
    CAST(SUM(used_mb) / 1024 AS decimal(10,2))                                                   AS used_space_gb,
    CAST(SUM(CASE WHEN file_type = 'ROWS' THEN used_mb ELSE 0 END) / 1024 AS decimal(10,2))      AS data_used_gb,
    CAST(SUM(CASE WHEN file_type = 'LOG'  THEN used_mb ELSE 0 END) / 1024 AS decimal(10,2))      AS log_used_gb,
    CAST(100.0 * SUM(used_mb) / NULLIF(SUM(allocated_mb), 0) AS decimal(5,2))                    AS used_pct
FROM #db_sizes where database_name NOT IN ('master','model','tempdb','msdb')
GROUP BY server_name, database_name
ORDER BY database_size_gb DESC;

DROP TABLE #db_sizes;