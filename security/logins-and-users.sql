/*
    Security / Logins and users
    Logins, database users, orphaned users, and effective permissions.
*/

-- Server principals: SQL logins, Windows logins, Windows groups.
SELECT name, type_desc, is_disabled, create_date, modify_date
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G')
ORDER BY type_desc, name;

-- SQL logins only, with password policy / expiration flags.
SELECT name, is_disabled, is_policy_checked, is_expiration_checked, modify_date
FROM sys.sql_logins
ORDER BY name;

-- Look up one login.
SELECT name, type_desc, is_disabled, sid
FROM sys.server_principals
WHERE name = N'YourLogin';

-- Tokens for the current connection: account plus the roles/groups it inherits.
SELECT * FROM sys.login_token;
GO

-- Users in the current database. Run after USE [YourDatabase].
-- type S = SQL user, U = Windows user, G = Windows group, A/X = role/cert/key based.
USE [YourDatabase];
GO
SELECT name, type_desc, authentication_type_desc, sid, create_date
FROM sys.database_principals
WHERE type IN ('S', 'U', 'G', 'A', 'X')
  AND name NOT IN ('guest', 'INFORMATION_SCHEMA', 'sys')
ORDER BY type_desc, name;
GO

-- Login-to-user mapping for the current database, with database role membership.
-- Server login joins database user on sid. NULL login = orphaned user.
USE [YourDatabase];
GO
SELECT
    sp.name        AS server_login,
    dp.name        AS database_user,
    DB_NAME()      AS database_name,
    r.name         AS database_role
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp
    ON sp.sid = dp.sid
LEFT JOIN sys.database_role_members drm
    ON drm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals r
    ON r.principal_id = drm.role_principal_id
WHERE dp.type IN ('S', 'U', 'G')
ORDER BY dp.name, r.name;
GO

-- Login-to-user mapping across all online databases (documented replacement for
-- the undocumented sp_msloginmappings). Cursor over ONLINE, multi-user dbs.
IF OBJECT_ID('tempdb..#login_mappings') IS NOT NULL DROP TABLE #login_mappings;
CREATE TABLE #login_mappings (
    database_name sysname,
    database_user sysname,
    server_login  sysname NULL,
    user_sid      varbinary(85)
);

DECLARE @db sysname, @sql nvarchar(max);
DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND user_access_desc = 'MULTI_USER'
      AND database_id > 4;          -- skip system databases

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        INSERT INTO #login_mappings (database_name, database_user, server_login, user_sid)
        SELECT ' + QUOTENAME(@db, '''') + N', dp.name, sp.name, dp.sid
        FROM ' + QUOTENAME(@db) + N'.sys.database_principals dp
        LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
        WHERE dp.type IN (''S'', ''U'', ''G'')
          AND dp.name NOT IN (''guest'', ''dbo'', ''sys'', ''INFORMATION_SCHEMA'');';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM db_cur INTO @db;
END
CLOSE db_cur;
DEALLOCATE db_cur;

SELECT * FROM #login_mappings ORDER BY database_name, database_user;
DROP TABLE #login_mappings;
GO

-- Orphaned users in the current database: a user whose sid has no matching login.
-- Common after restoring a database onto a different server.
USE [YourDatabase];
GO
SELECT dp.name AS orphaned_user, dp.type_desc, dp.sid
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp
    ON sp.sid = dp.sid
WHERE dp.type IN ('S', 'U', 'G')
  AND dp.authentication_type_desc <> 'NONE'
  AND sp.sid IS NULL
  AND dp.name NOT IN ('guest', 'dbo', 'sys', 'INFORMATION_SCHEMA');
GO

-- Fix an orphaned user by remapping it to an existing login (replaces
-- sp_change_users_login). Run in the affected database.
USE [YourDatabase];
GO
ALTER USER [YourUser] WITH LOGIN = [YourLogin];
GO

-- Membership and effective metadata of a Windows login or group (still useful
-- for resolving group expansion).
EXEC xp_logininfo 'YourDomain\YourLogin';
EXEC xp_logininfo 'YourDomain\YourGroup', 'members';
GO

-- Create a Windows login (individual account or group).
CREATE LOGIN [YourDomain\YourLogin] FROM WINDOWS;
GO

-- Create a SQL login. CHECK_POLICY OFF only where the app cannot meet the policy.
CREATE LOGIN [YourLogin] WITH PASSWORD = 'StrongP@ssw0rd!';
CREATE LOGIN [AppLogin]  WITH PASSWORD = 'StrongP@ssw0rd!', CHECK_POLICY = OFF;
GO

-- Map a login to a database user.
USE [YourDatabase];
GO
CREATE USER [YourUser] FOR LOGIN [YourLogin];
GO

-- Contained database user (no server login). Database must allow containment.
USE [YourDatabase];
GO
CREATE USER [ContainedUser] WITH PASSWORD = 'StrongP@ssw0rd!';
GO

-- Change database owner.
ALTER AUTHORIZATION ON DATABASE::[YourDatabase] TO [YourLogin];
GO

-- guest access. Enabling guest exposes the database to any connected login;
-- leave it revoked unless a specific scenario needs it.
USE [YourDatabase];
GO
-- GRANT CONNECT TO guest;   -- enable guest (intrusive, off by default)
REVOKE CONNECT FROM guest;   -- recommended default
GO

-- Add a login to a fixed server role (replaces sp_addsrvrolemember).
ALTER SERVER ROLE [sysadmin] ADD MEMBER [YourLogin];
GO

-- Effective permissions for a principal via EXECUTE AS, at server, database,
-- and object scope. REVERT always returns to the original context.
EXECUTE AS LOGIN = 'YourDomain\YourLogin';
    SELECT * FROM sys.fn_my_permissions(NULL, 'SERVER');
REVERT;
GO

USE [YourDatabase];
GO
EXECUTE AS USER = 'YourUser';
    SELECT * FROM sys.fn_my_permissions(NULL, 'DATABASE');
    SELECT * FROM sys.fn_my_permissions('dbo.YourObject', 'OBJECT')
    ORDER BY subentity_name, permission_name;
REVERT;
GO

-- Kerberos double-hop / linked-server delegation prerequisites.
-- For credentials to flow from client to SQL A to SQL B (linked server, no SQL login):
--   1. Register an SPN per instance: MSSQLSvc/host.fqdn:port under each service account.
--   2. Trust the SQL A service account for delegation (constrained, to SQL B's SPN).
--   3. Leave "Account is sensitive and cannot be delegated" OFF for the user being impersonated.
-- Self-mapping (sp_addlinkedserver / sp_addlinkedsrvlogin) is still valid in 2025:
EXEC sys.sp_addlinkedserver @server = N'YourLinkedServer', @srvproduct = N'',
    @provider = N'MSOLEDBSQL', @datasrc = N'host.fqdn,1433';
EXEC sys.sp_addlinkedsrvlogin @rmtsrvname = N'YourLinkedServer',
    @useself = N'TRUE';   -- pass through the caller's Windows identity (the second hop)
GO
