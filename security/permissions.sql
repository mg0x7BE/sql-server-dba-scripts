/*
    Security / Permissions
    Object, column, and schema level GRANT, REVOKE, and DENY.
*/

USE [YourDatabase];
GO

-- What permissions does the current login have at server, database, and object level.
-- Run first to see what you already hold before granting anything.
SELECT * FROM sys.fn_my_permissions(NULL, 'SERVER');
SELECT * FROM sys.fn_my_permissions(NULL, 'DATABASE');
SELECT * FROM sys.fn_my_permissions('dbo.YourTable', 'OBJECT')
ORDER BY subentity_name, permission_name;
GO

-- Test the effective permissions of another principal without logging in as them.
-- REVERT switches the context back. Set the login name before running.
EXECUTE AS LOGIN = 'DOMAIN\login';
    SELECT * FROM sys.fn_my_permissions(NULL, 'DATABASE');
    SELECT * FROM sys.fn_my_permissions('dbo.YourTable', 'OBJECT')
    ORDER BY subentity_name, permission_name;
REVERT;
GO

-- List the explicitly granted/denied permissions in the current database.
-- DENY (state W/D) overrides GRANT, so check here when access is unexpectedly blocked.
SELECT
    pr.name              AS principal_name,
    pr.type_desc         AS principal_type,
    perm.class_desc,
    perm.permission_name,
    perm.state_desc,
    OBJECT_SCHEMA_NAME(perm.major_id) AS [schema],
    OBJECT_NAME(perm.major_id)        AS [object]
FROM sys.database_permissions AS perm
JOIN sys.database_principals  AS pr ON pr.principal_id = perm.grantee_principal_id
ORDER BY pr.name, perm.class_desc, perm.permission_name;
GO

-- Script the GRANT statements held by one principal, across all permission classes.
-- Set the principal name; copy the output to recreate grants on another database.
-- Resolves DATABASE/SCHEMA/OBJECT/XML_SCHEMA_COLLECTION targets so none render blank.
DECLARE @PrincipalName sysname = N'YourRole';

SELECT
    perm.state_desc + N' ' + perm.permission_name
    + N' ON ' +
        CASE perm.class_desc
            WHEN 'DATABASE' THEN N'DATABASE::' + QUOTENAME(DB_NAME())
            WHEN 'SCHEMA'   THEN N'SCHEMA::' + QUOTENAME(SCHEMA_NAME(perm.major_id))
            WHEN 'OBJECT_OR_COLUMN' THEN N'OBJECT::'
                + QUOTENAME(OBJECT_SCHEMA_NAME(perm.major_id))
                + N'.' + QUOTENAME(OBJECT_NAME(perm.major_id))
            WHEN 'XML_SCHEMA_COLLECTION' THEN N'XML SCHEMA COLLECTION::'
                + QUOTENAME((SELECT name FROM sys.xml_schema_collections
                             WHERE xml_collection_id = perm.major_id))
            ELSE perm.class_desc + N'::' + CONVERT(nvarchar(20), perm.major_id)
        END
    + N' TO ' + QUOTENAME(pr.name)
    + CASE WHEN perm.state_desc = 'GRANT_WITH_GRANT_OPTION'
           THEN N' WITH GRANT OPTION' ELSE N'' END
    + N';' AS grant_statement
FROM sys.database_permissions AS perm
JOIN sys.database_principals  AS pr ON pr.principal_id = perm.grantee_principal_id
WHERE pr.name = @PrincipalName
ORDER BY perm.class_desc, perm.permission_name;
GO

-- Object-level GRANT. Two-part name resolves through OBJECT:: implicitly.
GRANT SELECT ON OBJECT::dbo.YourTable TO [YourRole];
GO

-- Column-level GRANT. Restricts SELECT to the listed columns only.
GRANT SELECT ON dbo.YourTable (Column1, Column2) TO [YourUser];
GO

-- WITH GRANT OPTION lets the grantee pass the permission on to others.
-- Avoid unless you specifically need delegated granting.
GRANT UPDATE ON dbo.YourTable TO [YourUser] WITH GRANT OPTION;
GO

-- REVOKE removes a previously granted/denied permission.
-- CASCADE also revokes any permissions the grantee passed on via WITH GRANT OPTION.
REVOKE UPDATE ON dbo.YourTable FROM [YourUser] CASCADE;
GO

-- Schema-level grants apply to every object in the schema, current and future.
-- EXECUTE covers procedures/functions; SELECT covers tables/views.
GRANT EXECUTE ON SCHEMA::YourSchema TO [YourUser];
GRANT SELECT  ON SCHEMA::YourSchema TO [YourUser];
GO

-- DENY blocks access even if a GRANT exists elsewhere (e.g. via role membership).
DENY SELECT ON SCHEMA::YourSchema TO [DOMAIN\login];
GO

-- Optional: log permission-denied errors (msg 229) to the SQL Server error log.
-- Instance-wide change; uncomment to apply.
-- EXEC msdb.dbo.sp_altermessage 229, 'WITH_LOG', 'true';
-- GO
