/*
    Programmability / Script objects
    Script out stored procedures and their schemas.
*/

-- Script stored procedures for redeploy: emits CREATE SCHEMA guards plus the
-- module text. Useful for moving procs between databases or rebuilding from scratch.
-- For a full, faithful object export prefer SSMS Generate Scripts or dbatools Export-DbaScript.
-- Run in the target database.
USE [YourDatabase];
GO

-- Filter: NULL = all procedures. Set @SchemaName / @ProcedureName to narrow it.
DECLARE @SchemaName    sysname = NULL;   -- e.g. 'dbo'
DECLARE @ProcedureName sysname = NULL;   -- e.g. 'usp_DoThing'

-- CREATE SCHEMA guards, one per distinct schema in scope. Run this batch first,
-- then the procedure definitions below, against the target database.
SELECT
    'IF SCHEMA_ID(''' + s.name + ''') IS NULL EXEC(''CREATE SCHEMA [' + s.name + ']'');' AS create_schema
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s
    ON s.schema_id = p.schema_id
WHERE (@SchemaName IS NULL OR s.name = @SchemaName)
  AND (@ProcedureName IS NULL OR p.name = @ProcedureName)
GROUP BY s.name
ORDER BY s.name;

-- Procedure definitions. sys.sql_modules.definition returns the full text and does
-- not truncate long modules the way OBJECT_DEFINITION can in some grid settings.
SELECT
    s.name AS schema_name,
    p.name AS procedure_name,
    m.definition
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s
    ON s.schema_id = p.schema_id
INNER JOIN sys.sql_modules AS m
    ON m.object_id = p.object_id
WHERE (@SchemaName IS NULL OR s.name = @SchemaName)
  AND (@ProcedureName IS NULL OR p.name = @ProcedureName)
ORDER BY s.name, p.name;
GO
