/**********************************************************************************************/
-- check if compression is enabled on a given database

SET NOCOUNT ON 
GO

SELECT DISTINCT
    SERVERPROPERTY('servername') [instance]
    ,DB_NAME() [database]
    ,QUOTENAME(OBJECT_SCHEMA_NAME(sp.object_id)) +'.'+QUOTENAME(Object_name(sp.object_id))[table]
    ,ix.name [index_name]
    ,sp.data_compression
    ,sp.data_compression_desc
FROM sys.partitions SP 
LEFT OUTER JOIN sys.indexes IX 
ON sp.object_id = ix.object_id 
and sp.index_id = ix.index_id
WHERE sp.data_compression <> 0
ORDER BY 2; 

/**********************************************************************************************/
-- get the details of the objects enabled for data compression.

SELECT 
    SCHEMA_NAME(sys.objects.schema_id) AS [SchemaName]
    ,OBJECT_NAME(sys.objects.object_id) AS [ObjectName]
    ,[rows]
    ,[data_compression_desc]
    ,[index_id] as [IndexID_on_Table]
FROM sys.partitions 
INNER JOIN sys.objects 
ON sys.partitions.object_id = sys.objects.object_id 
WHERE data_compression > 0 
AND SCHEMA_NAME(sys.objects.schema_id) <> 'SYS' 
ORDER BY SchemaName, ObjectName

/**********************************************************************************************/
-- To check for vardecimalstorage format compression run the following command

SELECT OBJECTPROPERTY(OBJECT_ID('<object name(s) from above command output>'),
            'TableHasVarDecimalStorageFormat') ;
GO

/**********************************************************************************************/
-- check if compression is present

SELECT schema_name(ST.schema_id) as [schema], st.name as table_name, b.name as idx_name,
       b.type_desc, sp.partition_number as partition, sp.data_compression as compression_desc,
       sp.data_compression_desc FROM sys.partitions SP
                                         INNER Join sys.indexes b ON b.object_id = sp.object_id AND b.index_id = sp.index_id
                                         INNER JOIN sys.tables ST ON
    st.object_id = sp.object_id
-- where data_compression = 2
order by 1, 2

/*
	0 off
	1 row compression
	2 page compression
*/

/**********************************************************************************************/
-- This code iterates through all indexes on the database and generates script to rebuild them with data compression.

SET NOCOUNT ON

/* Step 1 - get list of all indexes in database */
DECLARE  @Indexes TABLE
                  (
                      Row int IDENTITY,
                      IndexName nvarchar(128),
                      SchemaName nvarchar(64),
                      TableName nvarchar (64),
                      Iterator nvarchar(4)
                  )

INSERT INTO @Indexes
SELECT  si.name IndexName, schema_Name(so.schema_id) SchemaName, so.name TableName, cast(i.partition_number as nvarchar(4)) Iterator
FROM sys.indexes si
         JOIN sys.objects so ON si.[object_id] = so.[object_id]
         LEFT JOIN (select sp.object_id, sp.partition_number, sp.index_id
                    from (
                             select distinct object_id
                             from sys.partitions p
                             group by p.object_id, p.index_id
                             having COUNT(p.partition_id) > 1
                         ) as x
                             inner join sys.partitions sp ON sp.object_id = x.object_id
) i ON i.object_id = so.object_id and i.index_id = si.index_id
WHERE so.type = 'U'
  AND si.name IS NOT NULL
  and so.name not in ('Version', 'Nums')
ORDER BY
    so.name, si.index_id, i.partition_number

/* Step 2 - Generate scrip to rebuild them with compression */
DECLARE @row int
DECLARE @IndexName nvarchar(128)
DECLARE @SchemaName nvarchar(64)
DECLARE @TableName nvarchar(64)
DECLARE @Iterator nvarchar(4)

SET @row = (SELECT MAX(row) FROM @Indexes)

WHILE @row > 0
    BEGIN

        SELECT @IndexName = IndexName, @SchemaName = SchemaName, @TableName = TableName, @Iterator = Iterator
        FROM @Indexes
        WHERE Row = @row

        PRINT 'alter index [' + @IndexName + '] on [' + @SchemaName + '].['  + @TableName +
              CASE
                  WHEN @Iterator is null THEN '] rebuild with (data_compression=page, maxdop=12)'
                  ELSE '] rebuild partition = ' + @Iterator + ' with (data_compression=page, maxdop=12)'
                  END

        PRINT 'GO'
        PRINT 'PRINT ''Index Rebuild completed for: ' + @TableName +
              CASE WHEN @Iterator IS NOT NULL THEN ' partition ' + @Iterator ELSE '' END
            +  ' at '' + CONVERT (VARCHAR,GETDATE(),113)  '

        PRINT 'GO'

        SET @row = @row -1
    END