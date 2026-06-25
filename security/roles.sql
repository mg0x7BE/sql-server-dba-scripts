/*
    Security / Roles
    Server, database, and application roles; read-only role recipe.
*/

-- Test role membership inside code. IS_SRVROLEMEMBER for server roles,
-- IS_MEMBER for database roles and Windows groups. Snippet for use inside a
-- guarded procedure; ROLLBACK assumes an open transaction.
-- IF IS_MEMBER('YourRole') = 0
-- BEGIN
--     PRINT 'Caller is not a member of the required role';
--     ROLLBACK;
-- END;
-- GO

-- Server roles (fixed and user-defined). Fixed roles: sysadmin, securityadmin,
-- serveradmin, setupadmin, processadmin, diskadmin, dbcreator, bulkadmin, public.
SELECT name, principal_id, type_desc, is_fixed_role
FROM sys.server_principals
WHERE type = 'R'
ORDER BY is_fixed_role DESC, name;

-- Server role members.
SELECT r.name AS RoleName,
       p.name AS MemberName,
       p.type_desc AS MemberType
FROM sys.server_role_members AS srm
INNER JOIN sys.server_principals AS r ON srm.role_principal_id = r.principal_id
INNER JOIN sys.server_principals AS p ON srm.member_principal_id = p.principal_id
ORDER BY r.name, p.name;

-- Granted server-level permissions per principal.
SELECT p.name AS PrincipalName,
       sp.permission_name AS PermissionName,
       sp.state_desc AS State,
       sp.class_desc AS ClassDescription,
       sp.major_id AS MajorID
FROM sys.server_permissions AS sp
INNER JOIN sys.server_principals AS p ON sp.grantee_principal_id = p.principal_id
ORDER BY p.name, sp.permission_name;
GO

-- Add/remove a login to a fixed server role. Uncomment to run.
-- ALTER SERVER ROLE serveradmin ADD MEMBER [YourLogin];
-- GO
-- ALTER SERVER ROLE serveradmin DROP MEMBER [YourLogin];
-- GO

-- User-defined server role: create and add members. Uncomment to run.
-- USE master;
-- GO
-- CREATE SERVER ROLE srv_documenters;
-- GO
-- ALTER SERVER ROLE srv_documenters ADD MEMBER [YourLogin];
-- GO

-- Database roles (fixed and user-defined) in the current database.
-- Fixed: db_owner, db_securityadmin, db_accessadmin, db_backupoperator,
-- db_ddladmin, db_datawriter, db_datareader, db_denydatawriter, db_denydatareader, public.
USE [YourDatabase];
GO
SELECT name, principal_id, type_desc, is_fixed_role
FROM sys.database_principals
WHERE type = 'R'
ORDER BY is_fixed_role DESC, name;

-- Database role members with the member principal name.
SELECT r.name AS RoleName,
       p.name AS MemberName,
       p.type_desc AS MemberType
FROM sys.database_role_members AS drm
INNER JOIN sys.database_principals AS r ON drm.role_principal_id = r.principal_id
INNER JOIN sys.database_principals AS p ON drm.member_principal_id = p.principal_id
ORDER BY r.name, p.name;

-- Granted database-level permissions per principal.
SELECT p.name AS PrincipalName,
       dp.permission_name AS PermissionName,
       dp.state_desc AS State,
       dp.class_desc AS ClassDescription,
       dp.major_id AS MajorID
FROM sys.database_permissions AS dp
INNER JOIN sys.database_principals AS p ON dp.grantee_principal_id = p.principal_id
ORDER BY p.name, dp.permission_name;
GO

-- Compare roles between two databases (e.g. before/after a restore or a migration).
-- Lists user-defined and application roles present in the source DB and whether
-- a same-named role exists in the target DB.
DECLARE @SourceDb sysname = N'SourceDatabase';
DECLARE @TargetDb sysname = N'TargetDatabase';
DECLARE @sql nvarchar(max) = N'
SELECT src.name AS RoleName,
       src.type_desc AS RoleType,
       tgt.name AS RoleNameInTarget
FROM ' + QUOTENAME(@SourceDb) + N'.sys.database_principals AS src
LEFT JOIN ' + QUOTENAME(@TargetDb) + N'.sys.database_principals AS tgt
    ON tgt.name = src.name AND tgt.type IN (''R'',''A'')
WHERE src.type IN (''R'',''A'')   -- R = database role, A = application role
  AND src.is_fixed_role = 0
ORDER BY src.name;';
EXEC sys.sp_executesql @sql;
GO

-- Add/remove members on fixed database roles in the current database.
-- Uncomment to run.
-- USE [YourDatabase];
-- GO
-- ALTER ROLE db_datareader ADD MEMBER [YourUser];
-- GO
-- ALTER ROLE db_datareader DROP MEMBER [YourUser];
-- GO

-- User-defined database role: create, grant schema-level access, add a member.
-- Uncomment to run.
-- USE [YourDatabase];
-- GO
-- CREATE ROLE MarketingReaders AUTHORIZATION dbo;
-- GO
-- GRANT SELECT ON SCHEMA::Marketing TO MarketingReaders;
-- GO
-- ALTER ROLE MarketingReaders ADD MEMBER [YourUser];
-- GO

-- DESTRUCTIVE: drops a user-defined database role. Remove all members first.
-- Uncomment to run.
-- DROP ROLE MarketingReaders;
-- GO

-- Generate a CREATE ROLE + GRANT script for an existing role (object-level grants).
-- Prints the script; review before running it elsewhere. Does not execute.
USE [YourDatabase];
GO
DECLARE @RoleName sysname = N'YourRole';
DECLARE @Script nvarchar(max) = N'CREATE ROLE ' + QUOTENAME(@RoleName) + N';' + CHAR(13) + CHAR(10);
SELECT @Script = @Script
     + N'GRANT ' + dp.permission_name COLLATE Latin1_General_CI_AS
     + N' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(dp.major_id)) + N'.' + QUOTENAME(OBJECT_NAME(dp.major_id))
     + N' TO ' + QUOTENAME(@RoleName) + N';' + CHAR(13) + CHAR(10)
FROM sys.database_permissions AS dp
INNER JOIN sys.database_principals AS rol ON dp.grantee_principal_id = rol.principal_id
WHERE rol.name = @RoleName
  AND dp.class = 1   -- object or column
  AND dp.state IN ('G', 'W');
PRINT @Script;
GO

-- Application roles are legacy and discouraged: the app role's permissions
-- replace the user's own, the password is embedded in the app, and the
-- connection cannot revert until it closes. Kept as reference only.
-- USE [YourDatabase];
-- GO
-- CREATE APPLICATION ROLE MarketingApp WITH PASSWORD = 'UseAStrongSecretHere';
-- GO
-- GRANT SELECT ON SCHEMA::Marketing TO MarketingApp;
-- GO
-- EXEC sys.sp_setapprole 'MarketingApp', 'UseAStrongSecretHere';
-- GO

-- Read-only server role recipe. CONNECT ANY DATABASE lets the role into every
-- current and future database; SELECT ALL USER SECURABLES grants read on every
-- user object. Use for monitoring/reporting logins. Uncomment to run.
-- USE master;
-- GO
-- CREATE SERVER ROLE read_all;
-- GO
-- GRANT CONNECT ANY DATABASE TO read_all;
-- GO
-- GRANT SELECT ALL USER SECURABLES TO read_all;
-- GO
-- ALTER SERVER ROLE read_all ADD MEMBER [YourDomain\YourLogin];
-- GO

-- Verify effective permissions by impersonation. Run in a target user DB,
-- inspect, then REVERT. fn_my_permissions reports what the impersonated login can do.
-- Uncomment to run.
-- USE [YourDatabase];
-- GO
-- EXECUTE AS LOGIN = N'YourDomain\YourLogin';
-- GO
-- SELECT * FROM sys.login_token;
-- SELECT * FROM sys.user_token;
-- SELECT * FROM fn_my_permissions(NULL, 'SERVER');
-- SELECT * FROM fn_my_permissions(NULL, 'DATABASE');
-- SELECT * FROM fn_my_permissions('dbo.YourTable', 'OBJECT')
-- ORDER BY subentity_name, permission_name;
-- GO
-- REVERT;
-- GO
