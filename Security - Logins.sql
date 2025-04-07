/**********************************************************************************************/
-- Show all logins and mappings for specific database
use DATABASE_NAME_HERE;
go
SELECT 
	susers.[name] AS LogInAtServerLevel,
	users.[name] AS UserAtDBLevel,
	DB_NAME() AS [Database],              
	roles.name AS DatabaseRoleMembership
 from sys.database_principals users
  inner join sys.database_role_members link
   on link.member_principal_id = users.principal_id
  inner join sys.database_principals roles
   on roles.principal_id = link.role_principal_id
   inner join sys.server_principals susers
   on susers.sid = users.sid

/**********************************************************************************************/
-- list all the user mappings with database roles/permissions for a Login
CREATE TABLE #tempww (
    LoginName nvarchar(max),
    DBname nvarchar(max),
    Username nvarchar(max), 
    AliasName nvarchar(max)
)

INSERT INTO #tempww 
EXEC master..sp_msloginmappings 

-- display results
SELECT * 
FROM   #tempww 
ORDER BY dbname, username

-- cleanup
DROP TABLE #tempww

/**********************************************************************************************/
-- Find failed logins in Error Log
EXEC master..xp_ReadErrorLog 0, 1, 'Failed', 'login', NULL, NULL, 'desc' 

-- check logins
select * from master.dbo.syslogins where name = 'VFODSUSER'
select * from master.sys.server_principals where name = 'VFODSUSER'

-- fixing orphaned users
EXEC sp_change_users_login 'Report'
EXEC sp_change_users_login 'Auto_Fix', 'user'
ALTER USER dbuser WITH LOGIN = loginname; -- SQL Server 2005 SP2

-- show login info
exec xp_logininfo 'DOMAIN\login'

-- show role permissions
SELECT a.[name] + ' ' + v.[name] + ' ON ' + QuoteName(oo.[name]) 
+ '.' + QuoteName(o.[name]) + ' TO ' + QuoteName(u.[name]) COLLATE DATABASE_DEFAULT
   FROM dbo.sysprotects AS p
   JOIN master.dbo.spt_values AS a
      ON (a.number = p.protecttype
      AND 'T' = a.type)
   JOIN master.dbo.spt_values AS v
      ON (v.number = p.action
      AND 'T' = v.type)
   JOIN dbo.sysobjects AS o
      ON (o.id = p.id)
   JOIN dbo.sysusers AS oo
      ON (oo.uid = o.uid)
   JOIN dbo.sysusers AS u
      ON (u.uid = p.uid)
   WHERE  'CRMReaderRole' = u.name

/**********************************************************************************************/
-- Enable permission errors logging to ErrorLog
EXEC msdb.dbo.sp_altermessage 229,'WITH_LOG','true';

/**********************************************************************************************/
-- Test effective permissions

EXECUTE AS LOGIN = 'DOMAIN\login';
	SELECT * FROM fn_my_permissions(NULL, 'SERVER');
	GO
	
	use SKLFYOL01;
	GO
	
	SELECT * FROM fn_my_permissions (NULL, 'DATABASE');
	GO
	
	SELECT * FROM fn_my_permissions('SkySql.GetAllDataContext', 'OBJECT') 
    ORDER BY subentity_name, permission_name; 
    GO
REVERT

/**********************************************************************************************/
-- Configuration

-- Query the list of existing logins. 

SELECT * FROM sys.server_principals WHERE type IN ('S','U','G');
GO

-- Query the list of SQL Server logins. 

SELECT * FROM sys.sql_logins;
GO

-- Query the available logon tokens.

SELECT * FROM sys.login_token;
GO

-- Query the security IDs at both the server level and the database level
   
SELECT name, principal_id, sid 
FROM sys.server_principals 
WHERE name = 'TestUser';

SELECT name, principal_id, sid 
FROM sys.database_principals 
WHERE name = 'TestUser';
GO

-- Create a Windows login

CREATE LOGIN [ADVENTUREWORKS\user.name] FROM WINDOWS;
GO

-- Create a SQL Server login

CREATE LOGIN James WITH PASSWORD = 'Pa$$w0rd';
GO

-- Create a SQL Server login but disable the checking of account policy.

CREATE LOGIN HRApp WITH PASSWORD = 'Pa$$w0rd',
                        CHECK_POLICY = OFF;
GO

-- enable guest account

GRANT CONNECT TO guest;

-- prevent guest user from accessing a database

REVOKE CONNECT FROM guest;

-- modify database owner

ALTER AUTHORIZATION ON DATABASE::MarketDev
  TO [ADVENTUREWORKS\Administrator];

-- create user James for login James

CREATE USER James FOR LOGIN James;
GO

-- Create a user that is not associated with a login.

CREATE USER XRayApp WITH PASSWORD = 'Pa$$w0rd';
GO

/**********************************************************************************************/
--		==========  DELEGATION REQUIREMENTS ========================================================================== 

--		To illustrate the requirements for delegation between two SQL Server systems, consider the following scenario:

--		* A user logs on to a client computer that connects to a server that is running an instance of SQL
--		  Server, SQLSERVER1

--		* The user wants to run a distributed query against a database on another server, SQLSERVER2

--		* This scenario, in which one computer connects to another computer to connect to a third computer,
--		  is an example of a "double-hop".

--		Each server or computer that is involved in delegation needs to be configured appropriately.

--		==========  REQUIREMENTS FOR THE CLIENT ====================================================================== 

--		* The Windows authenticated login of the user must have access permissions to SQLSERVER1 and
--		  SQLSERVER2

--		* The user Active Directory property "Account is sensitive and cannot be delegated" must not be
--		  selected

--		* The client computer must be using TCP/IP or named pipes network connectivity.

--		==========  REQUIREMENTS FOR THE FIRST/MIDDLE SERVER (SQLSERVER1) ============================================ 

--		* The server must have a Server Principal Name (SPN) registered by the domain administrator.

--		* The account under which SQL Server is running must be trusted for delegation.

--		* The server must be using TCP/IP or named pipes network connectivity.

--		* The second server, SQLSERVER2, must be added as a linked server. This can be done by executing the
--		sp_addlinkedserver stored procedure or by configurations within SSMS. For example:

		EXEC sp_addlinkedserver 'SQLSERVER2', N'SQL Server'

--		* The linked server logins must be configured for self-mapping. This can be done by executing the
--		sp_addlinkedsrvlogin stored procedure. For example:

		EXEC sp_addlinkedsrvlogin 'SQLSERVER2', 'true'

--		========== REQUIREMENTS FOR THE SECOND SERVER (SQLSERVER2) ====================================================

--		* If using TCP/IP network connectivity, the server must have an SPN registered by the domain
--		  administrator.

--		* The server must be using TCP/IP or named pipes network connectivity.
--

/**********************************************************************************************/
-- Use Ring Buffer to find more information regarding login failures

SELECT CONVERT (varchar(30), GETDATE(), 121) as [RunTime],
dateadd (ms, rbf.[timestamp] - tme.ms_ticks, GETDATE()) as [Notification_Time],
cast(record as xml).value('(//SPID)[1]', 'bigint') as SPID,
cast(record as xml).value('(//ErrorCode)[1]', 'varchar(255)') as Error_Code,
cast(record as xml).value('(//CallingAPIName)[1]', 'varchar(255)') as [CallingAPIName],
cast(record as xml).value('(//APIName)[1]', 'varchar(255)') as [APIName],
cast(record as xml).value('(//Record/@id)[1]', 'bigint') AS [Record Id],
cast(record as xml).value('(//Record/@type)[1]', 'varchar(30)') AS [Type],
cast(record as xml).value('(//Record/@time)[1]', 'bigint') AS [Record Time],
tme.ms_ticks as [Current Time]
from sys.dm_os_ring_buffers rbf cross join sys.dm_os_sys_info tme
where rbf.ring_buffer_type = 'RING_BUFFER_SECURITY_ERROR' -- and cast(record as xml).value('(//SPID)[1]', 'int') = XspidNo
ORDER BY rbf.timestamp DESC

/*
Use Error_Code provided in Hex with "net helpmsg" cmd
For example Error_Code 0x139F -- net helpmsg 5023
*/

-- pull out information from the connectivity ring buffer
SELECT CONVERT (varchar(30), GETDATE(), 121) as [RunTime],
dateadd (ms, (rbf.[timestamp] - tme.ms_ticks), GETDATE()) as Time_Stamp,
cast(record as xml).value('(//Record/ConnectivityTraceRecord/RecordType)[1]', 'varchar(50)') AS [Action],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/RecordSource)[1]', 'varchar(50)') AS [Source],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/Spid)[1]', 'int') AS [SPID],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/RemoteHost)[1]', 'varchar(100)') AS [RemoteHost],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/RemotePort)[1]', 'varchar(25)') AS [RemotePort],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/LocalPort)[1]', 'varchar(25)') AS [LocalPort],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsInputBufferError)[1]', 'varchar(25)') AS [TdsInputBufferError],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsOutputBufferError)[1]', 'varchar(25)') AS [TdsOutputBufferError],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsInputBufferBytes)[1]', 'varchar(25)') AS [TdsInputBufferBytes],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/PhysicalConnectionIsKilled)[1]', 'int') AS [isPhysConnKilled],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/DisconnectDueToReadError)[1]', 'int') AS [DisconnectDueToReadError],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/NetworkErrorFoundInInputStream)[1]', 'int') AS [NetworkErrorFound],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/ErrorFoundBeforeLogin)[1]', 'int') AS [ErrorBeforeLogin],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/SessionIsKilled)[1]', 'int') AS [isSessionKilled],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/NormalDisconnect)[1]', 'int') AS [NormalDisconnect],
cast(record as xml).value('(//Record/ConnectivityTraceRecord/TdsDisconnectFlags/NormalLogout)[1]', 'int') AS [NormalLogout],
cast(record as xml).value('(//Record/@id)[1]', 'bigint') AS [Record Id],
cast(record as xml).value('(//Record/@type)[1]', 'varchar(30)') AS [Type],
cast(record as xml).value('(//Record/@time)[1]', 'bigint') AS [Record Time],
tme.ms_ticks as [Current Time]
FROM sys.dm_os_ring_buffers rbf
cross join sys.dm_os_sys_info tme
where rbf.ring_buffer_type = 'RING_BUFFER_CONNECTIVITY' and cast(record as xml).value('(//Record/ConnectivityTraceRecord/Spid)[1]', 'int') <> 0
ORDER BY rbf.timestamp DESC 