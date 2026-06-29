/*
    Diagnostics / Page inspection
    Locate and inspect data pages with sys.dm_db_page_info and DBCC PAGE.
*/

USE [YourDatabase];
GO

-- Locate a row physically: returns file:page:slot for each row.
-- Use to find which page holds a given row before inspecting it.
SELECT TOP (10)
    sys.fn_PhysLocFormatter(%%physloc%%) AS file_page_slot,
    *
FROM [Schema].[Table];
GO

-- Crack %%physloc%% into file_id, page_id, slot_id columns.
-- Handier than the formatted string when you need to feed page_id into dm_db_page_info.
SELECT TOP (10)
    pc.file_id,
    pc.page_id,
    pc.slot_id,
    t.*
FROM [Schema].[Table] AS t
CROSS APPLY sys.fn_PhysLocCracker(%%physloc%%) AS pc;
GO

-- Inspect a single page (2019+). No trace flag, returns a clean rowset.
-- Set @PageID from the locator queries above; @FileID is usually 1.
DECLARE @DatabaseID int = DB_ID();   -- current database
DECLARE @FileID     int = 1;
DECLARE @PageID     int = 0;         -- placeholder - set from fn_PhysLocCracker
SELECT *
FROM sys.dm_db_page_info(@DatabaseID, @FileID, @PageID, 'DETAILED');
GO

-- Find the page behind a wait/lock resource string like "5:1:169272".
-- Join the resource against PageResCracker, then expand it with dm_db_page_info.
SELECT
    pi.*
FROM (VALUES (CAST(0x3901020001000000 AS binary(8)))) AS r(page_resource)  -- placeholder page_resource bytes (binary(8))
CROSS APPLY sys.fn_PageResCracker(r.page_resource) AS prc
CROSS APPLY sys.dm_db_page_info(prc.db_id, prc.file_id, prc.page_id, 'DETAILED') AS pi;
GO

-- Same idea sourced live from current page-resource waits (PAGELATCH_*, page locks).
-- page_resource is exposed on dm_exec_requests and dm_tran_locks; crack it to a real page.
SELECT
    r.session_id,
    r.wait_type,
    pi.database_id,
    pi.file_id,
    pi.page_id,
    pi.page_type_desc,
    pi.object_id,
    pi.index_id
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.fn_PageResCracker(r.page_resource) AS prc
CROSS APPLY sys.dm_db_page_info(prc.db_id, prc.file_id, prc.page_id, 'DETAILED') AS pi
WHERE r.page_resource IS NOT NULL;
GO

-- Map database_id to name when you only have the number in a resource string.
SELECT database_id, name FROM sys.databases ORDER BY database_id;
SELECT DB_ID(N'YourDatabase') AS database_id, DB_NAME(DB_ID(N'YourDatabase')) AS database_name;
GO

-- Legacy alternative: DBCC PAGE. Needs trace flag 3604 to print to the client.
-- Prefer sys.dm_db_page_info above; keep this only for output styles 0-3 / older instances.
-- DBCC TRACESTATUS (-1);        -- list all active trace flags for this connection
-- DBCC TRACEON (3604);          -- route DBCC PAGE output to the client
-- -- DBCC PAGE (database_id, file_id, page_id, style)  style 0-3, 3 dumps full row data
-- DBCC PAGE (5, 1, 169272, 3);  -- placeholders - set db/file/page
-- DBCC TRACEOFF (3604);
