/**********************************************************************************************/
-- Create the credential
USE master;
GO

CREATE CREDENTIAL Agent_File_User 
WITH IDENTITY = N'DOMAIN\Agent_File_User',
SECRET = N'Pa$$w0rd';
GO

/**********************************************************************************************/
-- Query the available credentials
SELECT * FROM sys.credentials; 
GO