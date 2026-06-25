/*
    Data movement / Bulk import and export
    bcp out/in, BULK INSERT, OPENROWSET(BULK), format files, and minimal-logging rules.
*/

-- bcp runs from the OS command line, not in SSMS. Common switches:
-- -T trusted connection  -c character format  -n native format  -w unicode
-- -f format file  -x emit XML format file  -S server\instance  -d database
-- -b batch size  -F first row  -e error file
-- Use -c for portability across systems; -n is compact but SQL Server only.

-- Create an XML format file from an existing table (no rows moved).
-- bcp [YourDatabase].[Schema].[YourTable] format nul -T -c -x -f YourTable.xml -S YourServer\YourInstance

-- Export table data to a flat file.
-- bcp [YourDatabase].[Schema].[YourTable] out YourTable.dat -T -c -S YourServer\YourInstance

-- Import a flat file using a format file.
-- bcp [YourDatabase].[Schema].[YourTable] in YourTable.dat -T -f YourTable.xml -S YourServer\YourInstance

-- Import a CSV, skipping a header row, with a format file and batching.
-- bcp [YourDatabase].[Schema].[YourTable] in C:\Import\data.csv -T -f C:\Import\format.xml -F 2 -b 10000 -S YourServer\YourInstance


USE [YourDatabase];
GO

-- BULK INSERT loads a flat file in-process. Faster than bcp for server-local files.
-- Can be part of a user transaction; keep BATCHSIZE sane or the log grows even in simple recovery.
BULK INSERT [Schema].[YourTable]
FROM 'C:\Import\neworders.txt'
WITH (
    FIELDTERMINATOR = '|',
    ROWTERMINATOR = '|\n'
);
GO

-- BULK INSERT with a format file, skipping a header row and batching.
BULK INSERT [Schema].[YourTable]
FROM 'C:\Import\data.csv'
WITH (
    FORMATFILE = 'C:\Import\format.xml',
    FIRSTROW = 2,
    BATCHSIZE = 10000
);
GO

-- BULK INSERT from Azure Blob Storage (2016+). Needs a DATABASE SCOPED CREDENTIAL
-- and an EXTERNAL DATA SOURCE of TYPE = BLOB_STORAGE referenced via DATA_SOURCE.
-- BULK INSERT [Schema].[YourTable]
-- FROM 'container/path/data.csv'
-- WITH (
--     DATA_SOURCE = 'YourBlobDataSource',
--     FORMATFILE = 'container/path/format.xml',
--     FORMATFILE_DATA_SOURCE = 'YourBlobDataSource',
--     FIRSTROW = 2
-- );
-- GO

-- OPENROWSET(BULK ...) reads a file as a rowset, so you can filter/transform on the way in.
-- Useful when you only want some rows or columns, or need to add literal columns.
INSERT INTO [Schema].[YourTable]
SELECT *
FROM OPENROWSET(
    BULK 'C:\Import\data.csv',
    FORMATFILE = 'C:\Import\format.xml',
    FIRSTROW = 2
) AS src
WHERE src.LastName LIKE 'A%';
GO

-- Load a whole file as a single value (image, document, etc.) with SINGLE_BLOB.
-- SINGLE_CLOB for text, SINGLE_NCLOB for unicode text.
INSERT INTO [Schema].[Documents] (FileName, FileType, Document)
SELECT
    'data.txt'  AS FileName,
    '.txt'      AS FileType,
    BulkColumn
FROM OPENROWSET(BULK N'C:\Import\data.txt', SINGLE_BLOB) AS doc;
GO

-- OPENROWSET(BULK ...) from Azure Blob Storage (2017+) via DATA_SOURCE.
-- SELECT *
-- FROM OPENROWSET(
--     BULK 'container/path/data.csv',
--     DATA_SOURCE = 'YourBlobDataSource',
--     FORMATFILE = 'container/path/format.xml',
--     FORMATFILE_DATA_SOURCE = 'YourBlobDataSource',
--     FIRSTROW = 2
-- ) AS src;
-- GO

-- Minimal logging for bulk loads (BULK_LOGGED or SIMPLE recovery model).
-- Conditions:
--   - Recovery model is SIMPLE or BULK_LOGGED.
--   - Table is not being replicated.
--   - TABLOCK is specified on the load.
-- Rowstore index logging by table state:
--   - Heap + nonclustered indexes: data pages minimally logged; index pages minimally
--     logged only if the table is empty, otherwise fully logged.
--   - Clustered index, empty table: data and index pages minimally logged.
--   - Clustered index, non-empty table: data and index pages fully logged.
-- Clustered columnstore: loads of >= 102400 rows per batch go straight to a compressed
-- rowgroup and are minimally logged; smaller batches land in the delta store (fully logged).

-- Example minimal-logging load: set recovery model and pass TABLOCK.
-- ALTER DATABASE [YourDatabase] SET RECOVERY BULK_LOGGED;
-- GO
-- BULK INSERT [Schema].[YourTable]
-- FROM 'C:\Import\data.csv'
-- WITH (
--     TABLOCK,
--     FORMATFILE = 'C:\Import\format.xml',
--     FIRSTROW = 2,
--     BATCHSIZE = 102400
-- );
-- GO
-- ALTER DATABASE [YourDatabase] SET RECOVERY FULL;
-- GO
