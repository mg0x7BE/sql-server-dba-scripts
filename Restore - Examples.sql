/**********************************************************************************************/
-- Find only backup information

-- Use RESTORE HEADERONLY to get backup information from a backup device
RESTORE HEADERONLY 
FROM DISK = 'D:\MSSQLServer\Adv.bak';
GO

-- Use RESTORE FILELISTONLY to get a list of files that are contained in the backup.
-- S means filestream backup
RESTORE FILELISTONLY 
FROM DISK = 'D:\MSSQLServer\Adv.bak';
GO

-- Use RESTORE VERIFYONLY to check backup.
RESTORE VERIFYONLY 
FROM DISK = 'D:\MSSQLServer\Adv.bak';
GO

/**********************************************************************************************/
-- Restoring single file

-- Perform a tail-log backup
BACKUP LOG FTest
  TO DISK = 'D:\MSSQLServer\FTest.trn'
  WITH INIT, CONTINUE_AFTER_ERROR
GO

-- Restore only the missing file
RESTORE DATABASE FTest
  FILE = 'FTest1'
  FROM DISK = 'D:\MSSQLServer\FTest_full.bak'
  WITH NORECOVERY;
GO

-- Restore the tail-log backup
RESTORE LOG FTest
  FROM DISK = 'D:\MSSQLServer\FTest.trn'
  WITH RECOVERY;
GO

/**********************************************************************************************/
-- Point in time restore

-- Marking a Transaction
BEGIN TRAN UpdPrc WITH MARK 'Start of nightly update process';


-- Find the name of a transaction that was marked
SELECT * FROM msdb.dbo.logmarkhistory;


-- If the last backup of a set was inadvertently also restored WITH NORECOVERY, the database can be forced to recover by executing the following command:
RESTORE LOG databasename WITH RECOVERY;


-- Using STOPBEFOREMARK
RESTORE LOG RTest
  FROM DISK = 'D:\MSSQLServer\RTest.trn'
  WITH RECOVERY, STOPBEFOREMARK = 'PriorToInsert';
GO

-- Using STOPATMARK
RESTORE LOG RTest
  FROM DISK = 'D:\MSSQLServer\RTest.trn'
  WITH RECOVERY, STOPATMARK = 'PriorToInsert';
GO

/**********************************************************************************************/
-- Veryfing the backups

-- deletes all history prior to the date provided
EXEC sp_delete_backuphistory @oldest_date = '20090101';

-- deletes the history for a database named Market
EXEC sp_delete_database_backuphistory @database_name = 'Market';


/**********************************************************************************************/
-- Restore with STANDBY

ALTER DATABASE [MarketYields] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

RESTORE DATABASE [MarketYields] 
FROM  DISK = N'D:\MSSQLServer\MarketYields.bak' WITH  FILE = 2,  
MOVE N'MarketYields' TO N'D:\MKTG\MarketYields.mdf',  
MOVE N'MarketYields_log' TO N'L:\MKTG\MarketYields_log.ldf',  NORECOVERY,  NOUNLOAD,  STATS = 5;
GO

RESTORE DATABASE [MarketYields] 
FROM  DISK = N'D:\MSSQLServer\MarketYields.bak' WITH  FILE = 5,  NORECOVERY,  NOUNLOAD,  STATS = 5;
GO

RESTORE LOG [MarketYields] 
FROM  DISK = N'D:\MSSQLServer\MarketYields.bak' WITH  FILE = 6,  NORECOVERY,  NOUNLOAD,  STATS = 5;
GO

RESTORE LOG [MarketYields] 
FROM  DISK = N'D:\MSSQLServer\MarketYields.bak' WITH  FILE = 7,  STANDBY = N'L:\Log_Standby.bak',  NOUNLOAD,  STATS = 5;
GO

ALTER DATABASE [MarketYields] SET MULTI_USER;
GO

/**********************************************************************************************/