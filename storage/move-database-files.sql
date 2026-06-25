/*
    Storage / Move database files
    Generate ALTER DATABASE MODIFY FILE statements to relocate files.
*/

-- Generate the offline/copy/online steps to relocate a database's data and log files.
-- Print-only: review the output, then run the steps by hand.
-- Set the placeholders below. The physical file copy is a manual OS step between SET OFFLINE and SET ONLINE (instant file initialization helps data files, not logs).

SET NOCOUNT ON;

DECLARE @DatabaseName    sysname        = N'YourDatabase';   -- target database
DECLARE @DataPathNew     nvarchar(260)  = N'D:\Data';        -- new folder for ROWS files (no trailing backslash)
DECLARE @LogPathNew      nvarchar(260)  = N'L:\Log';         -- new folder for LOG files  (no trailing backslash)

DECLARE @nl char(2) = CHAR(13) + CHAR(10);
DECLARE @script nvarchar(max) = N'';

-- STEP 1: take the database offline (DESTRUCTIVE: rolls back open transactions, disconnects users)
SET @script = @script
    + N'-- STEP 1: take ' + QUOTENAME(@DatabaseName) + N' offline (rolls back open transactions)' + @nl
    + N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + @nl
    + N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET OFFLINE WITH ROLLBACK IMMEDIATE;' + @nl
    + N'GO' + @nl + @nl;

-- STEP 2: manual OS file copy (done outside SQL Server, target folders must already exist)
SET @script = @script
    + N'-- STEP 2: copy/move the files to the new path at the OS level, then continue' + @nl + @nl;

-- STEP 3: point the catalog at the new file locations
SET @script = @script
    + N'-- STEP 3: register the new file locations' + @nl;

SELECT @script = @script
    + N'-- source: ' + mf.physical_name + @nl
    + N'ALTER DATABASE ' + QUOTENAME(@DatabaseName)
    + N' MODIFY FILE ( NAME = ' + QUOTENAME(mf.name)
    + N', FILENAME = '''
    + CASE mf.type_desc
          WHEN N'ROWS' THEN @DataPathNew
          WHEN N'LOG'  THEN @LogPathNew
      END
    + N'\' + REVERSE(LEFT(REVERSE(mf.physical_name), CHARINDEX('\', REVERSE(mf.physical_name)) - 1))
    + N''' );' + @nl
FROM sys.master_files AS mf
WHERE mf.database_id = DB_ID(@DatabaseName)
  AND mf.type_desc IN (N'ROWS', N'LOG')
ORDER BY mf.type_desc, mf.file_id;

SET @script = @script + N'GO' + @nl + @nl;

-- STEP 4: bring the database back online
SET @script = @script
    + N'-- STEP 4: bring ' + QUOTENAME(@DatabaseName) + N' back online' + @nl
    + N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET ONLINE;' + @nl
    + N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' SET MULTI_USER;' + @nl
    + N'GO' + @nl;

PRINT @script;
