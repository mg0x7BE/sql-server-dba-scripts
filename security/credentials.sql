/*
    Security / Credentials
    SQL Server credentials, including managed identity and SAS.
*/

-- List server-level credentials.
-- First check before creating or troubleshooting a credential.
SELECT
    c.credential_id,
    c.name,
    c.credential_identity,
    c.create_date,
    c.modify_date
FROM sys.credentials AS c
ORDER BY c.name;
GO

-- Create a credential mapping to a Windows / domain account.
-- Used by SQL Agent proxies and external resource access.
-- Replace identity and secret placeholders; never store a real secret here.
CREATE CREDENTIAL [Agent_File_User]
    WITH IDENTITY = N'DOMAIN\Agent_File_User',
         SECRET = N'<secret-placeholder>';
GO

-- Credential backed by a Microsoft Entra managed identity.
-- Used for BACKUP TO URL and external data without storing a SAS token.
-- IDENTITY must be the literal string 'Managed Identity'; no SECRET.
CREATE CREDENTIAL [https://<storageaccount>.blob.core.windows.net/<container>]
    WITH IDENTITY = N'Managed Identity';
GO

-- Credential backed by a Shared Access Signature for Azure Blob Storage.
-- Used for BACKUP TO URL / RESTORE FROM URL and external data.
-- Credential name must match the container URL. SECRET is the SAS token
-- without the leading '?'. Replace the placeholder with a generated SAS.
CREATE CREDENTIAL [https://<storageaccount>.blob.core.windows.net/<container>]
    WITH IDENTITY = N'SHARED ACCESS SIGNATURE',
         SECRET = N'<sas-token-without-leading-question-mark>';
GO

-- Example use: back up a database to URL via the credential above.
-- The URL must fall under the credential name (container).
USE [YourDatabase];
GO
BACKUP DATABASE [YourDatabase]
    TO URL = N'https://<storageaccount>.blob.core.windows.net/<container>/YourDatabase.bak'
    WITH COMPRESSION, CHECKSUM, FORMAT, INIT;
GO

-- Rotate the secret on an existing credential (e.g. expired SAS token).
-- Replace placeholders with the current identity and the new secret.
ALTER CREDENTIAL [https://<storageaccount>.blob.core.windows.net/<container>]
    WITH IDENTITY = N'SHARED ACCESS SIGNATURE',
         SECRET = N'<new-sas-token-without-leading-question-mark>';
GO

-- Destructive: removes the credential. Anything depending on it (Agent
-- proxies, backups to URL) will fail. Review sys.credentials first.
-- Uncomment to run.
-- DROP CREDENTIAL [https://<storageaccount>.blob.core.windows.net/<container>];
-- GO
