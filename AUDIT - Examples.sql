/**********************************************************************************************/
-- Dynamic managemenent views (DMVs) and system views that can help to manage SQL Server Audit 


sys.dm_server_audit_status                -- Returns a row for each server audit 
                                          -- indicating the current state of the audit

sys.dm_audit_actions                      -- Returns a row for every audit action that 
                                          -- can be reported in the audit log and every 
										  -- action group that can be configured 
										  -- as part of an audit

sys.dm_audit_class_type_map               -- Returns a table that maps the class types 
                                          -- to class descriptions

sys.server_audits                         -- Contains one row for each SQL Server audit 
                                          -- in a server instance

sys.server_file_audits                    -- Contains extended information about the 
                                          -- file audit type in a SQL Server audit

sys.server_audit_specifications           -- Contains information about the server 
                                          -- audit specifications in a SQL Server audit

sys.server_audit_specification_details    -- Contains informaiton about the server 
                                          -- audit specification details (actions) 
										  -- in a SQL Server audit

sys.database_audit_specifications         -- Contains information about the database 
                                          -- audit specifications in a SQL Server audit

sys.database_audit_specification_details  -- Contains information about the database 
                                          -- audit specifications in a SQL Server audit

-- Create a SQL Server Audit and define its target as the Windows
-- application log

USE master;
GO
CREATE SERVER AUDIT MarketDevLog
    TO APPLICATION_LOG
    WITH ( QUEUE_DELAY = 1000,  ON_FAILURE = CONTINUE);
GO

-- Create a database audit specification for SELECT
-- activity on the Marketing schema

USE MarketDev;
GO
CREATE DATABASE AUDIT SPECIFICATION MarketingSelectSpec
  FOR SERVER AUDIT MarketDevLog
  ADD (SELECT ON SCHEMA::Marketing BY public);
GO

-- Enable the server audit

USE master;
GO
ALTER SERVER AUDIT MarketDevLog WITH (STATE = ON);
GO

-- Enable the MarketingSelectSpec audit specification

USE MarketDev;
GO
ALTER DATABASE AUDIT SPECIFICATION MarketingSelectSpec
  WITH (STATE = ON);
GO
  
-- Disable the server audit

USE master;
GO
ALTER SERVER AUDIT MarketDevLog WITH (STATE = OFF);
GO

-- Disable the MarketingSelectSpec audit specification

USE MarketDev;
GO
ALTER DATABASE AUDIT SPECIFICATION MarketingSelectSpec
  WITH (STATE = OFF);
GO

/**********************************************************************************************/

-- Create a SQL Server Audit and define its target as the folder

USE master;
GO
CREATE SERVER AUDIT MarketDevLogToFile
    TO FILE (FILEPATH = 'L:\SQLAudit\AuditLog');
GO
ALTER SERVER AUDIT MarketDevLogToFile WITH (STATE = ON);
GO

-- Create a database audit specification for SELECT
-- activity on the DirectMarketing schema

USE MarketDev;
GO
CREATE DATABASE AUDIT SPECIFICATION DirectMarketingSelectSpec
  FOR SERVER AUDIT MarketDevLogToFile
  ADD (SELECT ON SCHEMA::DirectMarketing BY public);
GO
ALTER DATABASE AUDIT SPECIFICATION DirectMarketingSelectSpec
  WITH (STATE = ON);
GO

-- Query the contents of the audit file

SELECT * FROM 
  sys.fn_get_audit_file('L:\SQLAudit\AuditLog\*',
  NULL,NULL);
GO

-- The folder that contains the audit logs often contains multiple audit files.
-- The sys.fn_get_audit_file function is used to retrieve those files. 
-- It takes three parameters:  the file_pattern, the initial_file_name, and the audit_record_offset.
-- The file_pattern provided can be ibn one of three formats:
/*
	<path>\*                                      -- Collects all audit files in the specified location

	<path>\LoginsAudit_{GUID}                     -- Collect all audit files that have the specified name and GUID pair

	<path>\LoginsAudit_{GUID}_00_29384.sqlaudit   -- Collect a specific audit file
*/

/**********************************************************************************************/

USE [master]
GO
CREATE SERVER AUDIT [Proseware Compliance Audit]
TO FILE 
(	FILEPATH = N'L:\SQLAudit\AuditLog'
	,MAXSIZE = 1 GB
	,MAX_ROLLOVER_FILES = 2147483647
	,RESERVE_DISK_SPACE = OFF
)
WITH
(	QUEUE_DELAY = 2000
	,ON_FAILURE = SHUTDOWN
)

GO

USE [master]
GO
CREATE SERVER AUDIT SPECIFICATION [Proseware Compliance Audit]
FOR SERVER AUDIT [Proseware Compliance Audit]
ADD (FAILED_LOGIN_GROUP),
ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
ADD (LOGIN_CHANGE_PASSWORD_GROUP)

GO

USE [MarketDev]
GO
CREATE DATABASE AUDIT SPECIFICATION [Proseware Compliance MarketDev Audit Specification]
FOR SERVER AUDIT [Proseware Compliance Audit]
ADD (BACKUP_RESTORE_GROUP),
ADD (DATABASE_OWNERSHIP_CHANGE_GROUP),
ADD (DATABASE_PERMISSION_CHANGE_GROUP),
ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
ADD (EXECUTE ON OBJECT::[Marketing].[MoveCampaignBalance] BY [public]),
ADD (UPDATE ON OBJECT::[Marketing].[CampaignBalance] BY [public])

GO

/**********************************************************************************************/