-- Find indexes with FillFactor NOT IN (0,100)

DECLARE @DB_Name varchar(100) 
DECLARE @Command nvarchar(max) 
DECLARE database_cursor CURSOR FOR 
SELECT name 
FROM MASTER.sys.sysdatabases 

OPEN database_cursor 

FETCH NEXT FROM database_cursor INTO @DB_Name 

WHILE @@FETCH_STATUS = 0 
BEGIN 
     SELECT @Command = '
		SELECT ''' + @DB_Name + ''' AS DatabaseName
			, ss.[name] + ''.'' + so.[name] AS TableName
			, si.name AS IndexName
			, si.type_desc AS IndexType
			, si.fill_factor AS [FillFactor]
			, ''ALTER INDEX '' + si.name + '' ON ' + @DB_Name + '.'' + ss.[name] + ''.'' + so.[name] + '' REBUILD WITH (FILLFACTOR = 100)'' as fix_me
		FROM ' + @DB_Name + '.sys.indexes si
		INNER JOIN ' + @DB_Name + '.sys.objects so ON si.object_id = so.object_id
		INNER JOIN ' + @DB_Name + '.sys.schemas ss ON so.schema_id = ss.schema_id
		WHERE si.name IS NOT NULL
		AND si.fill_factor NOT IN (0,100)
		AND so.type = ''U''
		ORDER BY si.fill_factor DESC'
	 --print @Command
     EXEC sp_executesql @Command 

     FETCH NEXT FROM database_cursor INTO @DB_Name 
END 

CLOSE database_cursor 
DEALLOCATE database_cursor 

