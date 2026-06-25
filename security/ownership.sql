/*
    Security / Ownership
    Normalize database and job ownership with a dry run.
*/

-- A single, consistent owner (sa) avoids orphaned ownership when the
-- creating login is dropped, and keeps ownership audits trivial.

-- List databases not owned by the intended principal.
-- Run first to see what is out of policy before changing anything.
DECLARE @OwnerLogin sysname = N'sa';

SELECT d.name AS database_name, SUSER_SNAME(d.owner_sid) AS current_owner
FROM sys.databases AS d
WHERE SUSER_SNAME(d.owner_sid) <> @OwnerLogin
ORDER BY d.name;
GO

-- List Agent jobs not owned by the intended principal.
-- 0x01 is the well-known sa SID; jobs owned by sa never break when a login is dropped.
SELECT j.name AS job_name, SUSER_SNAME(j.owner_sid) AS current_owner
FROM msdb.dbo.sysjobs AS j
WHERE j.owner_sid <> 0x01
ORDER BY j.name;
GO

-- Fix database ownership. Generates ALTER AUTHORIZATION per out-of-policy DB.
-- @WhatIf = 1 prints only; set to 0 to execute. Changing owner needs CONTROL on the DB.
DECLARE @OwnerLogin sysname = N'sa';
DECLARE @WhatIf bit = 1;
DECLARE @sql nvarchar(max);

SELECT @sql = STRING_AGG(
        CAST(N'ALTER AUTHORIZATION ON DATABASE::' + QUOTENAME(d.name)
             + N' TO ' + QUOTENAME(@OwnerLogin) + N';' AS nvarchar(max)),
        CHAR(13) + CHAR(10))
FROM sys.databases AS d
WHERE SUSER_SNAME(d.owner_sid) <> @OwnerLogin;

IF @sql IS NULL
    PRINT 'All databases already owned by ' + @OwnerLogin + '.';
ELSE IF @WhatIf = 1
    PRINT @sql;
ELSE
    EXEC sys.sp_executesql @sql;
GO

-- Fix Agent job ownership. Generates sp_update_job calls per out-of-policy job.
-- @WhatIf = 1 prints only; set to 0 to execute. Needs SQLAgentOperatorRole or sysadmin.
DECLARE @WhatIf bit = 1;
DECLARE @OwnerLogin sysname = N'sa';
DECLARE @sql nvarchar(max);

SELECT @sql = STRING_AGG(
        CAST(N'EXEC msdb.dbo.sp_update_job @job_name = N'
             + QUOTENAME(j.name, '''')
             + N', @owner_login_name = N' + QUOTENAME(@OwnerLogin, '''') + N';'
             AS nvarchar(max)),
        CHAR(13) + CHAR(10))
FROM msdb.dbo.sysjobs AS j
WHERE j.owner_sid <> 0x01;

IF @sql IS NULL
    PRINT 'All jobs already owned by ' + @OwnerLogin + '.';
ELSE IF @WhatIf = 1
    PRINT @sql;
ELSE
    EXEC sys.sp_executesql @sql;
GO
