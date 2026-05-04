/**********************************************************************************************/
-- Check data distribution in various partitions of the table & the indexed view.

SELECT OBJECT_NAME(p.object_id) as obj_name, p.index_id, p.partition_number, p.rows, a.type_desc, filegroup_name(filegroup_id) as filegroup_name
FROM sys.system_internals_allocation_units a
JOIN sys.partitions p
ON p.partition_id = a.container_id
WHERE p.object_id IN (OBJECT_ID(N'dbo.f_whatever'), OBJECT_ID(N'dbo.v_f_sales_whatever ')) -- table/view
ORDER BY obj_name, p.index_id, p.partition_number

/**********************************************************************************************/

-- Example: row counts in non-empty partitions:
SELECT OBJECT_NAME(p.object_id) as obj_name, p.partition_number, SUM(p.rows) as 'rows'
FROM sys.partitions p
WHERE p.object_id IN (OBJECT_ID(N'myschema.ErrorLog'), OBJECT_ID(N'myschema.ProcessLog ')) AND p.rows > 0
GROUP BY OBJECT_NAME(p.object_id), p.partition_number
ORDER BY 2 desc, 1 asc

/**********************************************************************************************/

-- Returns all rows from one partition of a partitioned table or index
SELECT * FROM Production.TransactionHistory
WHERE $PARTITION.TransactionRangePF1(TransactionDate) = 5 ;

/**********************************************************************************************/

-- Getting the partition number for a set of partitioning column values
/*
	USE AdventureWorks2008R2 ;
	GO
	CREATE PARTITION FUNCTION RangePF1 ( int )
	AS RANGE FOR VALUES (10, 100, 1000) ;
	GO
*/
SELECT $PARTITION.RangePF1 (10) ;
GO

/**********************************************************************************************/

-- Gets the number of rows in each nonempty partition of a partitioned table or index
USE AdventureWorks2008R2 ;
GO
SELECT $PARTITION.TransactionRangePF1(TransactionDate) AS Partition, 
COUNT(*) AS [COUNT] FROM Production.TransactionHistory 
GROUP BY $PARTITION.TransactionRangePF1(TransactionDate)
ORDER BY Partition ;
GO

/**********************************************************************************************/

