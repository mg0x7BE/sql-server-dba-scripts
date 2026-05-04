/**********************************************************************************************/
USE [master]
GO
-- create logins
CREATE LOGIN [DOMAIN\user1] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
CREATE LOGIN [DOMAIN\user2] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
CREATE LOGIN [DOMAIN\user3] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO

-- create new server role 
CREATE SERVER ROLE read_all;
GO
-- grant full connectivity and SELECT access
GRANT CONNECT ANY DATABASE TO read_all;
GO

GRANT SELECT ALL USER SECURABLES TO read_all;
GO
-- add newly created logins to the read_all server role
ALTER SERVER ROLE read_all ADD MEMBER [DOMAIN\user1];
GO
ALTER SERVER ROLE read_all ADD MEMBER [DOMAIN\user2];
GO
ALTER SERVER ROLE read_all ADD MEMBER [DOMAIN\user3];
GO

-- test new permissions:
use my_database;
GO
EXECUTE AS LOGIN = 'DOMAIN\user1';
	SELECT * FROM fn_my_permissions(NULL, 'SERVER');
	GO
	
	SELECT * FROM fn_my_permissions (NULL, 'DATABASE');
	GO
	
	SELECT * FROM fn_my_permissions('dbo.V_ESB_ST2_CUSTOMER', 'OBJECT') 
    ORDER BY subentity_name, permission_name; 
    GO

	SELECT top 10 name from sys.databases;
	GO

	SELECT TOP 1 * FROM [dbo].[CFS_ORGANIZATION]
	GO
REVERT
