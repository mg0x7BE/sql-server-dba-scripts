/**********************************************************************************************/
-- name:    Move DB files
-- version: v1.1
-- date:    29-Jan-2013
-- notes:   This script is safe to execute as it only prints the output without making changes
--          Please make sure to provide folders/LUNs that actually exist (it won't work otherwise)

DECLARE @path_SQLDAT_old nvarchar(max)   
DECLARE @path_SQLDAT_new nvarchar(max)   
DECLARE @path_SQLLOG_old nvarchar(max)  
DECLARE @path_SQLLOG_new nvarchar(max)
  
-- SQLDAT
SET @path_SQLDAT_old = 'S:\2crzuhedq100_userdbs_oltp_test_01\SQLDAT'  -- files to be moved
SET @path_SQLDAT_new = 'S:\2crzuhedq100_userdbs_oltp_test_02\SQLDAT'  -- new location 
-- SQLLOG
SET @path_SQLLOG_old = 'S:\2crzuhedq100_userdbs_oltp_test_01\SQLLOG'  -- files to be moved
SET @path_SQLLOG_new = 'S:\2crzuhedq100_userdbs_oltp_test_02\SQLLOG'  -- new location 

SET NOCOUNT ON;

DECLARE @database_id int 
DECLARE @database_name nvarchar(max)
DECLARE @script nvarchar(max)

DECLARE @master_files TABLE 
( 
	database_id       int,
	database_name     nvarchar(max),
    logical_name      nvarchar(max), 
    physical_name_old nvarchar(max),  
	physical_name_new nvarchar(max),   
    type_desc         nvarchar(max) 
);


INSERT INTO @master_files (database_id,database_name,logical_name,physical_name_old,physical_name_new,type_desc) 
SELECT [database_id],
	   DB_NAME([database_id]),
	   [name],
	   [physical_name],
	   CASE WHEN [type_desc] = 'ROWS' THEN REPLACE([physical_name],@path_SQLDAT_old,@path_SQLDAT_new)
			WHEN [type_desc] = 'LOG'  THEN REPLACE([physical_name],@path_SQLLOG_old,@path_SQLLOG_new)
			ELSE NULL
	   END as [physical_name_new],
	   type_desc  
FROM sys.master_files 
WHERE DB_NAME([database_id]) 
	  NOT IN ('master','tempdb','model','msdb','distribution') -- you may modify the WHERE clause to script
	                                                           -- only specific databases
AND [type_desc] IN ('ROWS','LOG')
AND [physical_name] <>
	   CASE WHEN [type_desc] = 'ROWS' THEN REPLACE([physical_name],@path_SQLDAT_old,@path_SQLDAT_new)
			WHEN [type_desc] = 'LOG'  THEN REPLACE([physical_name],@path_SQLLOG_old,@path_SQLLOG_new)
			ELSE NULL
	   END


DECLARE database_id_cursor CURSOR FOR 
SELECT DISTINCT [database_id] FROM @master_files
 
OPEN database_id_cursor    
FETCH NEXT FROM database_id_cursor INTO @database_id    
 
WHILE @@FETCH_STATUS = 0    
BEGIN 
	SET @script = ''
	SET @database_name = DB_NAME(@database_id)
	
	PRINT '----------------------------------------------------------------------------'
	PRINT '--  ' + @database_name
	PRINT ''
	PRINT '--  STEP 1: Set the database offline'
	PRINT ''
	PRINT 'ALTER DATABASE ' +  @database_name + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;'
	PRINT 'GO'
	PRINT 'ALTER DATABASE ' +  @database_name + ' SET OFFLINE WITH ROLLBACK IMMEDIATE;'
	PRINT 'GO'
	PRINT ''
	PRINT '--  STEP 2: Copy the files before proceeding'
	PRINT '--          Directory needs to exist for the ALTER to be successful'
	PRINT ''
	PRINT ''
	PRINT '--  STEP 3: ALTER the database'
	PRINT ''
	SELECT @script = @script
	+ '--  source: ' + physical_name_old + CHAR(10)
	+ 'ALTER DATABASE ' + quotename(database_name) + ' MODIFY FILE ( NAME = ' + quotename(logical_name) + ', FILENAME = ' + quotename(physical_name_new) + ' );' + CHAR(10) + 'GO' + CHAR(10)
	FROM @master_files WHERE database_id = @database_id

	PRINT @script
	PRINT ''
	PRINT '/* STEP 4: Set database online:'	
	PRINT ''
	PRINT '	ALTER DATABASE ' +  @database_name + ' SET ONLINE;'
	PRINT '	GO'
	PRINT '	ALTER DATABASE ' +  @database_name + ' SET MULTI_USER;'
	PRINT '	GO'
	PRINT '*/'

    FETCH NEXT FROM database_id_cursor INTO @database_id    
END    
CLOSE database_id_cursor    
DEALLOCATE database_id_cursor  
