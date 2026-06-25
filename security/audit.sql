/*
    Security / Audit
    SQL Server Audit: server and database audit specifications.
*/

-- Catalog views and DMVs for SQL Server Audit. Use these to find out what audits
-- and specs exist before changing anything.
/*
    sys.dm_server_audit_status                  -- current state of each server audit (running, file path, last event)
    sys.dm_audit_actions                        -- every auditable action and action group
    sys.dm_audit_class_type_map                 -- maps class types to descriptions
    sys.server_audits                           -- one row per server audit
    sys.server_file_audits                      -- file-target details for file audits
    sys.server_audit_specifications             -- server-level audit specs
    sys.server_audit_specification_details      -- actions in each server audit spec
    sys.database_audit_specifications           -- database-level audit specs
    sys.database_audit_specification_details    -- actions in each database audit spec
*/

-- Inventory all server audits and their current run state.
SELECT
    sa.audit_id,
    sa.name           AS audit_name,
    sa.type_desc      AS target_type,
    sa.on_failure_desc,
    sa.is_state_enabled,
    s.status_desc,
    s.audit_file_path,
    s.audit_file_size
FROM sys.server_audits AS sa
LEFT JOIN sys.dm_server_audit_status AS s
    ON sa.audit_id = s.audit_id
ORDER BY sa.name;
GO

-- Inventory server audit specifications and the actions they capture.
SELECT
    sas.name          AS server_spec_name,
    sas.is_state_enabled,
    sa.name           AS audit_name,
    d.audited_result,
    d.audit_action_name
FROM sys.server_audit_specifications AS sas
JOIN sys.server_audits AS sa
    ON sas.audit_guid = sa.audit_guid
JOIN sys.server_audit_specification_details AS d
    ON sas.server_specification_id = d.server_specification_id
ORDER BY sas.name, d.audit_action_name;
GO

-- Inventory database audit specifications in the current database.
USE [YourDatabase];
GO
SELECT
    das.name          AS database_spec_name,
    das.is_state_enabled,
    sa.name           AS audit_name,
    d.audited_result,
    d.audit_action_name,
    d.class_desc,
    OBJECT_SCHEMA_NAME(d.major_id) AS object_schema,
    OBJECT_NAME(d.major_id)        AS object_name
FROM sys.database_audit_specifications AS das
JOIN sys.server_audits AS sa
    ON das.audit_guid = sa.audit_guid
JOIN sys.database_audit_specification_details AS d
    ON das.database_specification_id = d.database_specification_id
ORDER BY das.name, d.audit_action_name;
GO

-- Create a server audit writing to a file target. The audit must be enabled separately.
-- ON_FAILURE controls what happens if the audit cannot write: CONTINUE keeps the
-- instance running and drops audit records, FAIL_OPERATION fails the audited statement,
-- SHUTDOWN stops the whole instance. SHUTDOWN has the widest blast radius - one full
-- disk can take the server down - so use it only where compliance demands it.
USE [master];
GO
CREATE SERVER AUDIT [YourServerAudit]
    TO FILE
    (   FILEPATH = N'<AuditFolderPath>'   -- e.g. N'D:\SQLAudit\'
        ,MAXSIZE = 1 GB
        ,MAX_ROLLOVER_FILES = 10
        ,RESERVE_DISK_SPACE = OFF
    )
    WITH
    (   QUEUE_DELAY = 1000
        ,ON_FAILURE = CONTINUE
    );
GO

-- A server audit can also write to the Windows event log instead of a file. TO SECURITY_LOG
-- needs the SQL Server service account granted "Generate security audits" and audit policy
-- enabled; TO APPLICATION_LOG works with no extra rights but anyone can read it.
USE [master];
GO
CREATE SERVER AUDIT [YourEventLogAudit]
    TO APPLICATION_LOG   -- or TO SECURITY_LOG
    WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO

-- Create a server audit specification for instance-level activity (logins, principal
-- and permission changes). Bind it to the server audit above.
USE [master];
GO
CREATE SERVER AUDIT SPECIFICATION [YourServerAuditSpec]
    FOR SERVER AUDIT [YourServerAudit]
    ADD (FAILED_LOGIN_GROUP),
    ADD (SUCCESSFUL_LOGIN_GROUP),
    ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
    ADD (LOGIN_CHANGE_PASSWORD_GROUP);
GO

-- Create a database audit specification for activity inside one database. Mix action
-- groups with specific object actions as needed. Bind it to the same server audit.
USE [YourDatabase];
GO
CREATE DATABASE AUDIT SPECIFICATION [YourDatabaseAuditSpec]
    FOR SERVER AUDIT [YourServerAudit]
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),
    ADD (SELECT ON SCHEMA::[YourSchema] BY [public]),
    ADD (UPDATE ON OBJECT::[YourSchema].[YourTable] BY [public]);
GO

-- Enable the audit and both specs. A spec produces no records until both it and its
-- server audit are ON.
USE [master];
GO
ALTER SERVER AUDIT [YourServerAudit] WITH (STATE = ON);
GO
ALTER SERVER AUDIT SPECIFICATION [YourServerAuditSpec] WITH (STATE = ON);
GO
USE [YourDatabase];
GO
ALTER DATABASE AUDIT SPECIFICATION [YourDatabaseAuditSpec] WITH (STATE = ON);
GO

-- Read audit files. file_pattern accepts:
--   <path>\*                              -- all audit files in the folder
--   <path>\<Name>_{GUID}                  -- all files for one audit (name + GUID pair)
--   <path>\<Name>_{GUID}_00_1234.sqlaudit -- one specific file
-- The other two args are initial_file_name and audit_record_offset; NULL reads from the start.
SELECT
    event_time,
    server_principal_name,
    database_name,
    schema_name,
    object_name,
    statement,
    action_id,
    succeeded
FROM sys.fn_get_audit_file(N'<AuditFolderPath>\*', NULL, NULL)
ORDER BY event_time DESC;
GO

-- Ledger (2022+) is complementary: it gives tamper-evident, cryptographically verifiable
-- history of data changes, where Audit records who did what. Use both if you need proof
-- of integrity, not just an activity trail.

-- DESTRUCTIVE: disabling and dropping stops collection and removes the audit objects.
-- Review before running. Specs must be disabled and dropped before the server audit.
/*
USE [YourDatabase];
GO
ALTER DATABASE AUDIT SPECIFICATION [YourDatabaseAuditSpec] WITH (STATE = OFF);
GO
DROP DATABASE AUDIT SPECIFICATION [YourDatabaseAuditSpec];
GO

USE [master];
GO
ALTER SERVER AUDIT SPECIFICATION [YourServerAuditSpec] WITH (STATE = OFF);
GO
DROP SERVER AUDIT SPECIFICATION [YourServerAuditSpec];
GO
ALTER SERVER AUDIT [YourServerAudit] WITH (STATE = OFF);
GO
DROP SERVER AUDIT [YourServerAudit];
GO
*/
