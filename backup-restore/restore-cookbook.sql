/*
    Backup and restore / Restore cookbook
    Restore techniques: headeronly, point in time, standby, tail log.
*/

-- Read header metadata from a backup device without restoring.
-- Shows backup type, LSNs, position, recovery model. Run first to plan a restore.
RESTORE HEADERONLY
FROM DISK = N'<BackupPath>\<YourDatabase>.bak';
GO

-- List logical/physical files inside a backup. Type 'S' = FILESTREAM.
-- Use to build MOVE clauses when restoring to different paths.
RESTORE FILELISTONLY
FROM DISK = N'<BackupPath>\<YourDatabase>.bak';
GO

-- Validate a backup is readable and complete without restoring it.
RESTORE VERIFYONLY
FROM DISK = N'<BackupPath>\<YourDatabase>.bak';
GO

-- Full + differential + log chain to a new database with relocated files.
-- All but the last restore use NORECOVERY so further backups can be applied.
RESTORE DATABASE [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>_full.bak'
    WITH MOVE N'<DataLogicalName>' TO N'<DataPath>\<YourDatabase>.mdf',
         MOVE N'<LogLogicalName>'  TO N'<LogPath>\<YourDatabase>_log.ldf',
         NORECOVERY, STATS = 5;
GO

RESTORE DATABASE [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>_diff.bak'
    WITH NORECOVERY, STATS = 5;
GO

RESTORE LOG [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>_log.trn'
    WITH RECOVERY, STATS = 5;
GO

-- Tail-log backup before a restore: captures log not yet backed up.
-- CONTINUE_AFTER_ERROR allows the tail backup even when the data files are damaged.
BACKUP LOG [YourDatabase]
    TO DISK = N'<BackupPath>\<YourDatabase>_tail.trn'
    WITH INIT, CONTINUE_AFTER_ERROR;
GO

-- Restore a single damaged file, then bring it current with the tail log.
RESTORE DATABASE [YourDatabase]
    FILE = N'<FileLogicalName>'
    FROM DISK = N'<BackupPath>\<YourDatabase>_full.bak'
    WITH NORECOVERY;
GO

RESTORE LOG [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>_tail.trn'
    WITH RECOVERY;
GO

-- Point-in-time recovery: stop the log replay at a wall-clock time.
RESTORE LOG [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>_log.trn'
    WITH RECOVERY, STOPAT = '<yyyy-mm-dd hh:mm:ss>';
GO

-- Mark a transaction so a restore can stop precisely at a logical event.
-- Run this in the application before a risky operation (e.g. nightly batch).
BEGIN TRAN UpdPrc WITH MARK 'Start of nightly update process';
-- ... work ...
-- COMMIT TRAN UpdPrc;
GO

-- Find names/LSNs of marked transactions when planning a marked restore.
SELECT * FROM msdb.dbo.logmarkhistory;
GO

-- Marked-transaction recovery: stop just before, or at, a named mark.
RESTORE LOG [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>_log.trn'
    WITH RECOVERY, STOPBEFOREMARK = '<MarkName>';
GO

RESTORE LOG [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>_log.trn'
    WITH RECOVERY, STOPATMARK = '<MarkName>';
GO

-- If the final backup was restored WITH NORECOVERY by mistake, force recovery.
RESTORE DATABASE [YourDatabase] WITH RECOVERY;
GO

-- STANDBY restore: database is read-only and queryable between log restores.
-- The standby file holds undo so further logs can still be applied.
-- Destructive: SINGLE_USER with ROLLBACK IMMEDIATE disconnects all other sessions.
ALTER DATABASE [YourDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

RESTORE DATABASE [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>.bak'
    WITH FILE = 2,
         MOVE N'<DataLogicalName>' TO N'<DataPath>\<YourDatabase>.mdf',
         MOVE N'<LogLogicalName>'  TO N'<LogPath>\<YourDatabase>_log.ldf',
         NORECOVERY, NOUNLOAD, STATS = 5;
GO

RESTORE LOG [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>.bak'
    WITH FILE = 3, NORECOVERY, NOUNLOAD, STATS = 5;
GO

RESTORE LOG [YourDatabase]
    FROM DISK = N'<BackupPath>\<YourDatabase>.bak'
    WITH FILE = 4, STANDBY = N'<LogPath>\<YourDatabase>_standby.bak',
         NOUNLOAD, STATS = 5;
GO

ALTER DATABASE [YourDatabase] SET MULTI_USER;
GO

-- Backup-history cleanup in msdb. Destructive: deletes history rows permanently.
-- Run a review SELECT first; uncomment the EXEC only after confirming the cutoff.
-- Removes all backup/restore history older than the cutoff date (all databases).
DECLARE @oldest_date datetime = DATEADD(MONTH, -3, GETDATE());

SELECT @oldest_date AS cutoff_date,
       COUNT(*)     AS rows_to_delete
FROM msdb.dbo.backupset
WHERE backup_finish_date < @oldest_date;

-- EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @oldest_date;
GO

-- Destructive: deletes all backup/restore history for one database.
-- EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'<YourDatabase>';
GO
