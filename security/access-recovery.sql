/*
    Security / Access recovery
    Regain sysadmin access via single-user mode; using the DAC.
*/

-- Single-user recovery: regain sysadmin when no one has it (lost sa, last
-- sysadmin removed). Run these in an OS shell, not in SSMS.
-- Stop the instance, then start it in single-user mode (-m). Restrict the
-- single connection to sqlcmd so app/agent connections cannot grab the slot.
-- Replace MSSQLSERVER with the service name (MSSQL$<INSTANCE> for a named one).
/*
    net stop MSSQLSERVER
    net start MSSQLSERVER /m"SQLCMD"
*/

-- Connect to the single-user instance with sqlcmd, using -E (Windows auth) as
-- a local admin. -S. is the default local instance; use -S.\<INSTANCE> if named.
/*
    sqlcmd -S. -E
*/

-- Once connected, create a login and grant sysadmin, then exit and restart
-- the service normally (net stop / net start without -m).
-- Uncomment the form you need and replace the principal placeholders.

-- Windows login (the account must already exist):
/*
CREATE LOGIN [DOMAIN\YourLogin] FROM WINDOWS;
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [DOMAIN\YourLogin];
GO
*/

-- SQL login (mixed-mode auth must be enabled):
/*
CREATE LOGIN [recovery_admin] WITH PASSWORD = N'<strong-password>';
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [recovery_admin];
GO
*/

-- Dedicated Admin Connection (DAC): a reserved scheduler/connection for
-- emergencies when the instance is hung or refusing normal logins. Only one
-- DAC at a time, and the connecting login needs sysadmin.
-- Connect with sqlcmd -A, or from SSMS use the ADMIN: prefix in the server name
-- (ADMIN:<server> - open a query window, not Object Explorer).
/*
    sqlcmd -S. -E -A
    sqlcmd -S.\YourInstance -E -A
*/

-- Allow the DAC from a remote machine (off by default, local-only).
-- Useful when you cannot RDP to the host. Uncomment to apply.
/*
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXEC sys.sp_configure 'remote admin connections', 1;
RECONFIGURE;
GO
*/

-- Check whether remote DAC is currently enabled.
SELECT name, value_in_use
FROM sys.configurations
WHERE name = 'remote admin connections';
GO
