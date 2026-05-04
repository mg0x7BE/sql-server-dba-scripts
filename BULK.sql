/**********************************************************************************************/
-- using bcp

format  -- create a format file
-T      -- Integrated security is used to connect to the server
-c      -- Character data type is used for the export. Character data type provides 
        -- the highest compatibility between different types of system. An
        -- alternative option -n would use the SQL Sercer native format, which is a 
        -- more compact format but which can only be used for import/export to
        -- other SQL Server systems.
-f      -- The name of the format file
-x      -- The format file should be created as XML file
-S      -- can be used to supply a server name or a server name and an instance name.


-- example: Creating a format file

bcp Adv.Sales.Currency format nul -T -c -x -f Cur.xml

-- example: Exporting data into a file:

bcp Adv.Sales.Currency out Cur.dat -T -c

-- example: Importing data using a format file:

bcp tempdb.Sales.Currency2 in Cur.dat -T -f Cur.xml

-- example: Importing data into the DirectMarketing.ExchangeRate table

bcp MarketDev.DirectMarketing.ExchangeRate in ExchangeRates.csv -T -f ExchangeRates.xml -S Proseware

/**********************************************************************************************/
-- BULK INSERT runs in the process of SQL Server, can omit constraint checking and trigger firing and can be part of a user-definied transaction
-- Care must be taken to ensure that the size of the data batches that are imported withing a single transaction are not excessive, or significant
-- log file growth might occur, even when the database is in simple recovery model.

BULK INSERT AdventureWorks.Sales.OrderDetail
FROM 'f:\orders\neworders.txt'
WITH ( FIELDTERMINATOR = '|',
	   ROWTERMINATOR = '|\n'
	 );
GO

BULK INSERT dbo.ProspectName
FROM 'D:\10775A_Labs\10775A_08_PRJ\10775A_08_PRJ\ProspectExport.csv' 
WITH ( FORMATFILE='D:\10775A_Labs\10775A_08_PRJ\10775A_08_PRJ\format.fmt',
       BATCHSIZE=200,
       FIRSTROW=2
     );
GO
/**********************************************************************************************/
-- OPENROWSET Function

SELECT *
	FROM OPENROWSET(
	BULK 'c:\mssql\export.csv',
	FORMATFILE = 'c:\mssql\format.fmt',
	FIRSTROW = 2) AS a;
GO

INSERT INTO Sales.Documents(FileName, FileType, Document)
SELECT 'JanuarySales.txt' AS FileName,
	   '.txt' AS FileType,
	   *
FROM OPENROWSET(BULK N'K:\JanuarySales.txt', SINGLE_BLOB) AS Document;
GO

INSERT INTO dbo.ImportData
SELECT * 
	FROM OPENROWSET( BULK 'D:\10775A_Labs\10775A_08_PRJ\10775A_08_PRJ\ProspectExport.csv', 
			FORMATFILE = 'D:\10775A_Labs\10775A_08_PRJ\10775A_08_PRJ\format.fmt',
			FIRSTROW = 2) AS a
	WHERE LastName LIKE 'A%';
GO

/**********************************************************************************************/
-- Minimal Logging
-- types of restrictions that must be met for minimal logging to be applied:

-- The table is not being replicated
-- Table locking is specified (using TABLOCK)
-- If the table has no clustered index but has one or more nonclustered indexes, data pages are always minimally logged. How index pages are logged, however, depends on whether the table is empty.
-- If the table is empty, index pages are minimally logged.
-- If table is non-empty, index pages are fully logged.
-- If the table has a clustered index and is empty, both data and index pages are minimally logged.
-- If a table has a clustered index and is non-empty, data pages and index pages are both fully logged regardless of the recovery model.

/**********************************************************************************************/