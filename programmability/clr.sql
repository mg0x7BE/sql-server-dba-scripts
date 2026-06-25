/*
    Programmability / CLR
    CLR integration under clr strict security with signed assemblies.
*/

-- Current CLR config and runtime state. Run first to see if CLR is enabled and what is loaded.
SELECT name, value, value_in_use, is_dynamic
FROM sys.configurations
WHERE name IN ('clr enabled', 'clr strict security');

-- CLR properties: hosted CLR version and state.
SELECT * FROM sys.dm_clr_properties;

-- One row per managed user assembly loaded into the server address space.
SELECT * FROM sys.dm_clr_loaded_assemblies;

-- One row per application domain in the server.
SELECT * FROM sys.dm_clr_appdomains;

-- CLR tasks currently running. Useful to spot in-flight managed code.
SELECT * FROM sys.dm_clr_tasks;

-- For CLR query execution and cached plans see performance/plan-cache.sql and
-- performance/query-store.sql (sys.dm_exec_query_stats / sys.dm_exec_cached_plans).

-- Assemblies cataloged in the current database, with permission set and signing state.
-- permission_set_desc SAFE/EXTERNAL_ACCESS/UNSAFE; clr_name shows the strong name if signed.
SELECT a.name, a.permission_set_desc, a.is_visible, a.clr_name, a.create_date
FROM sys.assemblies AS a
WHERE a.is_user_defined = 1;

-- Trusted assembly hashes (an escape hatch from clr strict security). Empty is normal.
SELECT * FROM sys.trusted_assemblies;
GO

-- Enable CLR integration on the instance. Instance-wide change, leave commented until needed.
-- clr strict security has been ON by default since 2017: every assembly must be signed
-- (asymmetric key or certificate mapped to a login holding UNSAFE/EXTERNAL ASSEMBLY) or
-- trusted via sys.sp_add_trusted_assembly, regardless of permission set.
/*
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'clr enabled', 1;
RECONFIGURE;
*/
GO

-- Deploy a signed assembly under clr strict security. Template, commented out:
-- it grants UNSAFE ASSEMBLY and catalogs server objects, and the 0x... values are
-- placeholders. Replace placeholders, then run the steps in order.
-- Sign the DLL with a strong-name key or Authenticode cert at build time, then:
--   1. create an asymmetric key (or certificate) in master from the same key/cert
--   2. create a login from that key and grant UNSAFE ASSEMBLY (or EXTERNAL ASSEMBLY)
--   3. CREATE ASSEMBLY in the user database
-- Prefer FROM 0x... binary over a file path: no SQL Server service-account file access
-- needed, and the assembly travels with the script.
/*
USE [master];
GO

-- FROM BINARY = 0x... is the public key extracted from the signing key/cert.
-- IF NOT EXISTS guard so re-running the step does not error.
IF NOT EXISTS (SELECT 1 FROM sys.asymmetric_keys WHERE name = N'ClrSigningKey')
    CREATE ASYMMETRIC KEY ClrSigningKey
    FROM BINARY = 0xPUBLICKEYBYTES;
    -- Alternative, needs service-account file access:
    --   FROM EXECUTABLE FILE = N'C:\Path\To\SignedAssembly.dll';
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'ClrSigningLogin')
    CREATE LOGIN ClrSigningLogin FROM ASYMMETRIC KEY ClrSigningKey;
GO

GRANT UNSAFE ASSEMBLY TO ClrSigningLogin;
GO

USE [YourDatabase];
GO

-- Catalog the signed assembly. FROM 0x... is the signed DLL bytes (placeholder).
-- File-path form (CREATE ASSEMBLY ... FROM 'C:\...dll') still works but needs the
-- service account to read the path; binary form avoids that.
CREATE ASSEMBLY NextCharacter
FROM 0xASSEMBLYBYTES
WITH PERMISSION_SET = SAFE;
GO

-- Bind a T-SQL function to the managed method: AssemblyName.[Namespace.]Class.Method.
-- Here: assembly NextCharacter, class NextCharacter (no namespace), method Replace.
CREATE FUNCTION dbo.NextCharacter(@input NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS EXTERNAL NAME NextCharacter.NextCharacter.Replace;
GO

-- Smoke test the deployed function.
SELECT dbo.NextCharacter('test');
GO
*/

-- Escape hatch: trust a specific unsigned assembly by SHA2_512 hash instead of signing it.
-- Weaker than signing - the hash must be re-added whenever the assembly is rebuilt.
-- Get the hash, then register it (commented; run only if you accept the assembly).
/*
DECLARE @asm VARBINARY(MAX) = 0xASSEMBLYBYTES;
DECLARE @hash VARBINARY(64) = HASHBYTES('SHA2_512', @asm);
EXEC sys.sp_add_trusted_assembly @hash = @hash, @description = N'NextCharacter';
*/
GO

-- For the data-masking use case the original assembly served, prefer the native features:
-- Dynamic Data Masking (ALTER COLUMN ... ADD MASKED WITH ...) or Always Encrypted.
