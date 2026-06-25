/*
    Programmability / Triggers
    DML and DDL trigger examples and trigger inventory.
*/

-- Inventory all database and server triggers with enabled/disabled state.
-- First stop when chasing unexpected side effects on DML/DDL.
SELECT
    'DATABASE' AS scope,
    t.name,
    OBJECT_SCHEMA_NAME(t.parent_id) + '.' + OBJECT_NAME(t.parent_id) AS parent,
    t.type_desc,
    CASE WHEN t.is_disabled = 1 THEN 'DISABLED' ELSE 'ENABLED' END AS state,
    CASE WHEN t.is_instead_of_trigger = 1 THEN 'INSTEAD OF' ELSE 'AFTER' END AS firing
FROM sys.triggers AS t
WHERE t.parent_class = 1   -- object-level (table/view) triggers
UNION ALL
SELECT
    'SERVER' AS scope,
    st.name,
    NULL AS parent,
    st.type_desc,
    CASE WHEN st.is_disabled = 1 THEN 'DISABLED' ELSE 'ENABLED' END AS state,
    NULL AS firing
FROM sys.server_triggers AS st
ORDER BY scope, name;
GO

-- DML audit trigger: record color changes on dbo.Product into an audit table.
-- Fires only when the Color column is actually touched; handles multi-row updates.
-- Run in the target database.
USE [YourDatabase];
GO

-- Audit table (create once).
IF OBJECT_ID('dbo.ProductColorAudit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductColorAudit
    (
        AuditID     BIGINT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
        ProductID   INT NOT NULL,
        OldColor    NVARCHAR(50) NULL,
        NewColor    NVARCHAR(50) NULL,
        ChangedUtc  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_Product_Color_Update
ON dbo.Product
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(Color)
    BEGIN
        INSERT dbo.ProductColorAudit (ProductID, OldColor, NewColor)
        SELECT i.ProductID, d.Color, i.Color
        FROM inserted AS i
        INNER JOIN deleted AS d
            ON i.ProductID = d.ProductID
        WHERE ISNULL(i.Color, '') <> ISNULL(d.Color, '');
    END;
END;
GO

-- For pure change tracking, temporal tables (SYSTEM_VERSIONING) or CDC are
-- usually a better fit than hand-rolled DML audit triggers.

-- DDL trigger: log schema changes (CREATE/ALTER/DROP) in the current database.
-- Catches who changed objects and when. Reads the event via EVENTDATA().
-- Run in the target database.
USE [YourDatabase];
GO

-- Log table (create once).
IF OBJECT_ID('dbo.DdlChangeAudit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DdlChangeAudit
    (
        AuditID      BIGINT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
        EventType    SYSNAME NOT NULL,
        ObjectName   SYSNAME NULL,
        LoginName    SYSNAME NULL,
        EventTimeUtc DATETIME2(3) NOT NULL,
        EventData    XML NULL
    );
END;
GO

CREATE OR ALTER TRIGGER TR_DDL_SchemaChangeAudit
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE,
    CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE,
    CREATE_VIEW, ALTER_VIEW, DROP_VIEW
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @event XML = EVENTDATA();

    INSERT dbo.DdlChangeAudit (EventType, ObjectName, LoginName, EventTimeUtc, EventData)
    SELECT
        @event.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
        @event.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname'),
        @event.value('(/EVENT_INSTANCE/LoginName)[1]', 'sysname'),
        SYSUTCDATETIME(),
        @event;
END;
GO
