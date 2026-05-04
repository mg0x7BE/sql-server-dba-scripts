/**********************************************************************************************/
-- compare roles
select 
	su.name as 'RoleName', 
	su.uid as 'RoleId', 
	su.isapprole as 'IsAppRole',
	su2.name as 'RoleName2'
from 
	[BizTalkDTADB.bak].dbo.sysusers su -- source
left join
	[BizTalkDTADB].dbo.sysusers su2
on
	su2.name = su.name
where 
	su.issqlrole = 1
or 
	su.isapprole = 1 
order by 
	su.name

/**********************************************************************************************/
-- copy role permissions
declare @RoleName varchar(50) 
SET @RoleName =  'HWS_ADMIN_USER'

declare @Script varchar(max);
set @Script = 'CREATE ROLE ' + @RoleName + char(13)
select @script = @script + 'GRANT ' + prm.permission_name + ' ON ' + OBJECT_NAME(major_id) + ' TO ' + rol.name + char(13) COLLATE Latin1_General_CI_AS 
from sys.database_permissions prm
    join sys.database_principals rol on
        prm.grantee_principal_id = rol.principal_id
where rol.name = @RoleName
print @script

/**********************************************************************************************/
-- decision-making within code example
-- IS_SRVROLEMEMBER tests for server role membership
-- IS_MEMBER tests for database role membership, can also test for Windows group membership

IF IS_MEMBER('BankManagers') = 0
BEGIN
	PRINT 'Operation is only for bank manager use';
	ROLLBACK;
END;

/**********************************************************************************************/
-- TEST THE ROLE ASSIGNMENTS
/**********************************************************************************************/

-- check the available tokens for Darren Parker
USE MarketDev;
GO

EXECUTE AS LOGIN = 'AdventureWorks\Darren.Parker';
GO

SELECT * FROM sys.login_token;
GO

SELECT * FROM sys.user_token;
GO

REVERT;
GO

/**********************************************************************************************/
-- SERVER ROLES
/**********************************************************************************************/

-- server-scoped permissions
select * from sys.server_permissions

-- View the available fixed server roles
SELECT * FROM sys.server_principals WHERE type = 'R';

-- View the members of the server roles
SELECT r.name AS RoleName,
       p.name AS PrincipalName 
FROM sys.server_role_members AS srm
INNER JOIN sys.server_principals AS r
ON srm.role_principal_id = r.principal_id
INNER JOIN sys.server_principals AS p
ON srm.member_principal_id = p.principal_id;
GO

-- List the server permissions that have been granted.
SELECT p.name AS PrincipalName,
       sp.permission_name AS PermissionName, 
       class_desc AS ClassDescription, 
       Major_id AS MajorID
FROM sys.server_permissions AS sp
INNER JOIN sys.server_principals AS p
ON sp.grantee_principal_id = p.principal_id
ORDER BY p.name, sp.permission_name;
GO

-- typical server-scoped permissions
		--	ALTER ANY DATABASE
		--	BACKUP DATABASE
		--	CONNECT SQL
		--	CREATE DATABASE
		--	VIEW ANY DEFINITION
		--	ALTER TRACE
		--	BACKUP LOG
		--	CONTROL SERVER
		--	SHUTDOWN
		--	VIEW SERVER STATE

-- fixed server roles
		sysadmin      -- Perform any activity						-- CONTROL SERVER (with GRANT option)
		dbcreator     -- Create ad alter databases					-- ALTER ANY DATABASE
		diskadmin     -- Manage disk files							-- ALTER RESOURCES
		serveradmin   -- Configure server-wide settings				-- ALTER ANY ENDPOINT
																	-- ALTER RESOURCES
																	-- ALTER SERVER STATE
																	-- ALTER SETTINGS
																	-- SHUTDOWN
																	-- VIEW SERVER STATE
		securityadmin -- Manage and audit server logins				-- ALTER ANY LOGIN
		processadmin  -- Manage SQL Server processes				-- ALTER ANY CONNECTION
																	-- ALTER SERVER STATE
		bulkadmin     -- Run the BULK INSERT statement              -- ADMINISTER BULK OPERATIONS
		setupadmin    -- Configure replication and linked servers   -- ALTER ANY LINKED SERVER

-- Add login to the serveradmin role
ALTER SERVER ROLE serveradmin ADD MEMBER SampleLogin;
GO

ALTER SERVER ROLE sysadmin ADD MEMBER [AdventureWorks\Jeff.Hay];
GO

-- Drop login from the serveradmin role
ALTER SERVER ROLE serveradmin DROP MEMBER SampleLogin;
GO

/**********************************************************************************************/
-- public server role

-- public Serve Role by default, is granted:
VIEW ANY DATABASE permission
CONNECT permission on default endpoints

/**********************************************************************************************/
-- user-defined server roles (new to SQL Server 2012)

-- Create a new user-defined server role
USE master;
GO
CREATE SERVER ROLE srv_documenters;
GO

/**********************************************************************************************/
-- DATABASE ROLES
/**********************************************************************************************/

-- fixed database roles example
USE AdventureWorks;
GO
ALTER ROLE db_datareader
	ADD MEMBER James;
GO
ALTER ROLE db_backupoperator 
	DROP MEMBER Mod10Login;
GO

USE MarketDev;
GO
ALTER ROLE db_owner 
	ADD MEMBER [AdventureWorks\ITSupport];
GO
ALTER ROLE db_datareader 
	ADD MEMBER DBMonitorApp;
GO

-- assign specific permissions example
GRANT CREATE TABLE TO HRManager;
GO
GRANT VIEW DEFINITION TO James;
GO

-- overview of fixed database roles
			db_owner           -- Perform any configuration and maintenance activities on the DB and can drop it
			db_securityadmin   -- Modify role membership and manage permissions
			db_accessadmin     -- Add or remove access to the DB for logins
			db_backupoperator  -- Back up the DB
			db_ddladmin        -- Run any DDL command in the DB
			db_datawriter      -- Add, delete, or change data in all user tables
			db_datareader      -- Read all data from all user tables
			db_denydatawriter  -- Cannot add, delete, or change data in user tables
			db_denydatareader  -- Cannot read any data in user tables

-- review the permission assignments
select * from sys.database_permissions

--  View the available database roles
SELECT * FROM sys.database_principals WHERE type = 'R';
GO

--  View the members of the database roles
SELECT r.name AS RoleName,
       p.name AS PrincipalName 
FROM sys.database_role_members AS drm
INNER JOIN sys.database_principals AS r
ON drm.role_principal_id = r.principal_id
INNER JOIN sys.database_principals AS p
ON drm.member_principal_id = p.principal_id;
GO


/**********************************************************************************************/
-- USER-DEFINED DATABASE ROLES
/**********************************************************************************************/

-- user-defined database roles example
USE MarketDev;
GO

CREATE ROLE MarketingReaders
	AUTHORIZATION dbo;
GO

GRANT SELECT ON SCHEMA::Marketing
	TO MarketingReaders;
GO

CREATE ROLE HR_LimitedAccess AUTHORIZATION dbo;
GO

ALTER ROLE HR_LimitedAccess ADD MEMBER Mod10Login;
GO

ALTER ROLE HR_LimitedAccess DROP MEMBER Mod10Login;
GO

DROP ROLE HR_LimitedAccess;
GO

-- user-defined database roles example 2
USE MarketDev;
GO

CREATE ROLE SalesTeam;
GO

CREATE ROLE SalesManagers;
GO

ALTER ROLE SalesTeam ADD MEMBER [AdventureWorks\SalesPeople];
GO
ALTER ROLE SalesTeam ADD MEMBER [AdventureWorks\CreditManagement];
GO
ALTER ROLE SalesTeam ADD MEMBER [AdventureWorks\CorporateManagers];
GO
ALTER ROLE SalesManagers ADD MEMBER [AdventureWorks\Darren.Parker];
GO

/**********************************************************************************************/
-- APPLICATION ROLES
/**********************************************************************************************/

-- Application roles are used to enable permissions for users only when they are running particular applications.
-- Note: The permissions of the application role replace the permissions of the user!

-- sp_setapprole
-- sp_unsetapprole

-- Example step 1: Create an application role

USE MarketDev;
GO
CREATE APPLICATION ROLE MarketingApp
  WITH PASSWORD = 'Pa$$w0rd';
GO

-- Example step 2:  Assign permissions to the application role

GRANT SELECT ON SCHEMA::Marketing 
  TO MarketingApp;
GO

-- Example step 3:  View the current user tokens.

SELECT * FROM sys.user_token;
GO

-- Example step 4:  Set the application role.

EXEC sp_setapprole MarketingApp, 'Pa$$w0rd';
GO

-- Example step 5:  View the current user tokens.

SELECT * FROM sys.user_token;
GO