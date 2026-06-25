/*
    Backup and restore / History and coverage
    Backup history, coverage and freshness, and live restore progress.
*/

-- To reach backup storage prefer BACKUP TO URL with a SAS or Managed Identity
-- credential, or a secured UNC path granted to the service account.
-- No drive mapping and no xp_cmdshell.

-- Latest backup per database, all types. Quick freshness overview.
SELECT
    d.name,
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) AS last_full,
    MAX(CASE WHEN bs.type = 'I' THEN bs.backup_finish_date END) AS last_diff,
    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) AS last_log
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON d.name = bs.database_name
WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
GROUP BY d.name
ORDER BY d.name;

-- Databases missing a recent full backup. Coverage gap check.
-- Adjust the freshness window as needed.
DECLARE @FullWithinHours int = 24;

SELECT
    d.name,
    d.recovery_model_desc,
    MAX(bs.backup_finish_date) AS last_full
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON d.name = bs.database_name
    AND bs.type = 'D'
WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
GROUP BY d.name, d.recovery_model_desc
HAVING MAX(bs.backup_finish_date) IS NULL
    OR MAX(bs.backup_finish_date) < DATEADD(HOUR, -@FullWithinHours, SYSDATETIME())
ORDER BY last_full;
GO

-- Databases in FULL or BULK_LOGGED missing a recent log backup. Log chain gap check.
DECLARE @LogWithinHours int = 1;

SELECT
    d.name,
    d.recovery_model_desc,
    MAX(bs.backup_finish_date) AS last_log
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON d.name = bs.database_name
    AND bs.type = 'L'
WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
    AND d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
GROUP BY d.name, d.recovery_model_desc
HAVING MAX(bs.backup_finish_date) IS NULL
    OR MAX(bs.backup_finish_date) < DATEADD(HOUR, -@LogWithinHours, SYSDATETIME())
ORDER BY last_log;
GO

-- Backup history with device path and sizes.
-- Leave @DatabaseName empty for all databases.
DECLARE @DatabaseName sysname = N'';

SELECT
    bs.database_name,
    bs.media_set_id,
    bs.backup_finish_date,
    bs.type,
    bs.backup_size,
    bs.compressed_backup_size,
    mf.physical_device_name
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS mf
    ON bs.media_set_id = mf.media_set_id
WHERE (@DatabaseName = N'' OR bs.database_name = @DatabaseName)
ORDER BY bs.backup_finish_date DESC;
GO

-- Restore history for a database. When and from where it was last restored.
DECLARE @DatabaseName sysname = N'YourDatabase';

SELECT
    rs.destination_database_name,
    rs.restore_date,
    bmf.physical_device_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    bs.database_name,
    bs.user_name
FROM msdb.dbo.restorehistory AS rs
INNER JOIN msdb.dbo.backupset AS bs
    ON rs.backup_set_id = bs.backup_set_id
INNER JOIN msdb.dbo.backupmediafamily AS bmf
    ON bs.media_set_id = bmf.media_set_id
WHERE rs.destination_database_name = @DatabaseName
ORDER BY rs.restore_date DESC;
GO

-- Live backup and restore progress with engine-supplied ETA.
-- Match the target database by database_id, not by text search.
SELECT
    r.session_id,
    r.command,
    d.name AS database_name,
    d.state_desc,
    r.start_time,
    r.percent_complete,
    DATEADD(SECOND, r.estimated_completion_time / 1000, SYSDATETIME()) AS estimated_completion_time,
    t.text AS query
FROM sys.dm_exec_requests AS r
LEFT JOIN sys.databases AS d
    ON r.database_id = d.database_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.command IN ('BACKUP DATABASE', 'BACKUP LOG', 'RESTORE DATABASE', 'RESTORE LOG')
ORDER BY r.percent_complete DESC;
