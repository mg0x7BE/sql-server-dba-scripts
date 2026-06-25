/*
    SQL Server Agent Jobs
    Job/step/schedule inventory, run outcomes and history, running/failed/long-running jobs, proxies and credentials.
*/

-- Job, step and schedule inventory. One row per job step with its schedule name.
-- Quick map of what runs, in what subsystem, on which schedule.
SELECT j.name AS job_name,
       CASE j.enabled WHEN 1 THEN 'Yes' ELSE 'No' END AS job_enabled,
       s.step_id,
       s.step_name,
       s.subsystem,
       sch.name AS schedule_name
FROM msdb.dbo.sysjobs AS j
INNER JOIN msdb.dbo.sysjobsteps AS s
    ON s.job_id = j.job_id
LEFT JOIN msdb.dbo.sysjobschedules AS js
    ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules AS sch
    ON sch.schedule_id = js.schedule_id
ORDER BY j.name, s.step_id;
GO

-- Jobs with PowerShell or CmdExec steps.
-- These reach outside SQL; worth knowing for security and proxy reviews.
SELECT j.name AS job_name,
       s.step_id,
       s.step_name,
       s.subsystem
FROM msdb.dbo.sysjobsteps AS s
INNER JOIN msdb.dbo.sysjobs AS j
    ON s.job_id = j.job_id
WHERE s.subsystem IN ('PowerShell', 'CmdExec')
ORDER BY j.name, s.step_id;
GO

-- Last run outcome per job (most recent step_id = 0 row).
-- First stop for "did the job succeed last night".
SELECT j.name AS job_name,
       msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS last_run,
       CASE jh.run_status
           WHEN 0 THEN 'Failed'
           WHEN 1 THEN 'Succeeded'
           WHEN 2 THEN 'Retry'
           WHEN 3 THEN 'Canceled'
           WHEN 4 THEN 'In progress'
       END AS run_status,
       STUFF(STUFF(RIGHT('000000' + CONVERT(varchar(6), jh.run_duration), 6), 5, 0, ':'), 3, 0, ':') AS duration_hhmmss,
       jh.message
FROM msdb.dbo.sysjobs AS j
INNER JOIN (
    SELECT job_id, MAX(instance_id) AS instance_id
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
    GROUP BY job_id
) AS last_run
    ON last_run.job_id = j.job_id
INNER JOIN msdb.dbo.sysjobhistory AS jh
    ON jh.instance_id = last_run.instance_id
ORDER BY j.name;
GO

-- Recent job-level outcomes in the last 24 hours.
-- Morning health check after an overnight batch.
SELECT j.name AS job_name,
       msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS run_time,
       CASE jh.run_status
           WHEN 0 THEN 'Failed'
           WHEN 1 THEN 'Succeeded'
           WHEN 2 THEN 'Retry'
           WHEN 3 THEN 'Canceled'
           WHEN 4 THEN 'In progress'
       END AS run_status,
       STUFF(STUFF(RIGHT('000000' + CONVERT(varchar(6), jh.run_duration), 6), 5, 0, ':'), 3, 0, ':') AS duration_hhmmss,
       jh.message
FROM msdb.dbo.sysjobhistory AS jh
INNER JOIN msdb.dbo.sysjobs AS j
    ON jh.job_id = j.job_id
WHERE jh.step_id = 0
  AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time) > DATEADD(day, -1, SYSDATETIME())
ORDER BY run_time DESC;
GO

-- Currently running jobs.
-- Use before a deploy, restart, or to spot a job that is stuck.
SELECT j.name AS job_name,
       ja.start_execution_date AS started,
       DATEDIFF(second, ja.start_execution_date, SYSDATETIME()) AS running_seconds,
       ja.last_executed_step_id AS last_step
FROM msdb.dbo.sysjobactivity AS ja
INNER JOIN msdb.dbo.sysjobs AS j
    ON j.job_id = ja.job_id
WHERE ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL
  AND ja.session_id = (
      SELECT MAX(session_id) FROM msdb.dbo.syssessions
  )
ORDER BY started;
GO

-- Failing job steps, newest first.
-- Drill into which step failed and the error text after a job failure.
SELECT j.name AS job_name,
       jh.step_id,
       jh.step_name,
       msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS run_time,
       CASE jh.run_status
           WHEN 0 THEN 'Failed'
           WHEN 2 THEN 'Retry'
           WHEN 3 THEN 'Canceled'
       END AS run_status,
       STUFF(STUFF(RIGHT('000000' + CONVERT(varchar(6), jh.run_duration), 6), 5, 0, ':'), 3, 0, ':') AS duration_hhmmss,
       jh.message
FROM msdb.dbo.sysjobhistory AS jh
INNER JOIN msdb.dbo.sysjobs AS j
    ON jh.job_id = j.job_id
WHERE jh.step_id > 0
  AND jh.run_status <> 1
ORDER BY jh.run_date DESC, jh.run_time DESC;
GO

-- Full schedule report: every job, decoded recurrence, avg duration and next run.
-- The go-to view of when each job fires and how long it usually takes.
SELECT j.name AS job_name,
       cat.name AS category,
       SUSER_SNAME(j.owner_sid) AS owner_login,
       CASE j.enabled WHEN 1 THEN 'Yes' ELSE 'No' END AS job_enabled,
       CASE sch.enabled WHEN 1 THEN 'Yes' ELSE 'No' END AS schedule_enabled,
       j.description,
       CASE sch.freq_type
           WHEN 1 THEN 'Once'
           WHEN 4 THEN 'Daily'
           WHEN 8 THEN 'Weekly'
           WHEN 16 THEN 'Monthly'
           WHEN 32 THEN 'Monthly relative'
           WHEN 64 THEN 'When SQL Server Agent starts'
           WHEN 128 THEN 'When the CPU(s) become idle'
           ELSE ''
       END AS occurs,
       CASE sch.freq_type
           WHEN 1 THEN 'Once'
           WHEN 4 THEN 'Every ' + CONVERT(varchar, sch.freq_interval) + ' day(s)'
           WHEN 8 THEN 'Every ' + CONVERT(varchar, sch.freq_recurrence_factor) + ' week(s) on '
               + STUFF(
                   CASE WHEN sch.freq_interval & 1 = 1 THEN ', Sunday' ELSE '' END
                 + CASE WHEN sch.freq_interval & 2 = 2 THEN ', Monday' ELSE '' END
                 + CASE WHEN sch.freq_interval & 4 = 4 THEN ', Tuesday' ELSE '' END
                 + CASE WHEN sch.freq_interval & 8 = 8 THEN ', Wednesday' ELSE '' END
                 + CASE WHEN sch.freq_interval & 16 = 16 THEN ', Thursday' ELSE '' END
                 + CASE WHEN sch.freq_interval & 32 = 32 THEN ', Friday' ELSE '' END
                 + CASE WHEN sch.freq_interval & 64 = 64 THEN ', Saturday' ELSE '' END, 1, 2, '')
           WHEN 16 THEN 'Day ' + CONVERT(varchar, sch.freq_interval) + ' of every '
               + CONVERT(varchar, sch.freq_recurrence_factor) + ' month(s)'
           WHEN 32 THEN 'The '
               + CASE sch.freq_relative_interval
                     WHEN 1 THEN 'First'
                     WHEN 2 THEN 'Second'
                     WHEN 4 THEN 'Third'
                     WHEN 8 THEN 'Fourth'
                     WHEN 16 THEN 'Last'
                 END
               + CASE sch.freq_interval
                     WHEN 1 THEN ' Sunday'
                     WHEN 2 THEN ' Monday'
                     WHEN 3 THEN ' Tuesday'
                     WHEN 4 THEN ' Wednesday'
                     WHEN 5 THEN ' Thursday'
                     WHEN 6 THEN ' Friday'
                     WHEN 7 THEN ' Saturday'
                     WHEN 8 THEN ' Day'
                     WHEN 9 THEN ' Weekday'
                     WHEN 10 THEN ' Weekend Day'
                 END
               + ' of every ' + CONVERT(varchar, sch.freq_recurrence_factor) + ' month(s)'
           ELSE ''
       END AS occurs_detail,
       CASE sch.freq_subday_type
           WHEN 1 THEN 'Once at ' + CONVERT(varchar(8), DATEADD(second, sch.active_start_time, 0), 108)
           WHEN 2 THEN 'Every ' + CONVERT(varchar, sch.freq_subday_interval) + ' second(s)'
           WHEN 4 THEN 'Every ' + CONVERT(varchar, sch.freq_subday_interval) + ' minute(s)'
           WHEN 8 THEN 'Every ' + CONVERT(varchar, sch.freq_subday_interval) + ' hour(s)'
           ELSE ''
       END AS frequency,
       CONVERT(decimal(10, 2), hist.avg_duration_sec) AS avg_duration_sec,
       CASE js.next_run_date
           WHEN 0 THEN NULL
           ELSE msdb.dbo.agent_datetime(js.next_run_date, js.next_run_time)
       END AS next_run
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysjobschedules AS js
    ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules AS sch
    ON js.schedule_id = sch.schedule_id
INNER JOIN msdb.dbo.syscategories AS cat
    ON j.category_id = cat.category_id
LEFT JOIN (
    SELECT job_id,
           AVG(DATEDIFF(second, 0,
               STUFF(STUFF(RIGHT('000000' + CONVERT(varchar(6), run_duration), 6), 5, 0, ':'), 3, 0, ':'))
               * 1.0) AS avg_duration_sec
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
    GROUP BY job_id
) AS hist
    ON hist.job_id = j.job_id
-- WHERE j.name LIKE '%<NamePart>%'
ORDER BY j.name;
GO

-- Long running scheduled jobs: enabled, scheduled, avg duration over the threshold.
-- Capacity/window planning - which jobs eat the most time and when they run next.
-- max_duration_sec is the worst-case run: size the maintenance window to that, not the average.
DECLARE @MinAvgDurationSec int = 60;

SELECT job_name,
       description,
       occurs,
       occurs_detail,
       frequency,
       avg_duration_sec,
       avg_duration_sec / 60.0 AS avg_duration_min,
       max_duration_sec,
       max_duration_sec / 60.0 AS max_duration_min,
       next_run
FROM (
    SELECT j.name AS job_name,
           SUSER_SNAME(j.owner_sid) AS owner_login,
           CASE j.enabled WHEN 1 THEN 'Yes' ELSE 'No' END AS job_enabled,
           CASE sch.enabled WHEN 1 THEN 'Yes' ELSE 'No' END AS schedule_enabled,
           j.description,
           CASE sch.freq_type
               WHEN 1 THEN 'Once'
               WHEN 4 THEN 'Daily'
               WHEN 8 THEN 'Weekly'
               WHEN 16 THEN 'Monthly'
               WHEN 32 THEN 'Monthly relative'
               WHEN 64 THEN 'When SQL Server Agent starts'
               WHEN 128 THEN 'When the CPU(s) become idle'
               ELSE ''
           END AS occurs,
           CASE sch.freq_type
               WHEN 1 THEN 'Once'
               WHEN 4 THEN 'Every ' + CONVERT(varchar, sch.freq_interval) + ' day(s)'
               WHEN 8 THEN 'Every ' + CONVERT(varchar, sch.freq_recurrence_factor) + ' week(s) on '
                   + STUFF(
                       CASE WHEN sch.freq_interval & 1 = 1 THEN ', Sunday' ELSE '' END
                     + CASE WHEN sch.freq_interval & 2 = 2 THEN ', Monday' ELSE '' END
                     + CASE WHEN sch.freq_interval & 4 = 4 THEN ', Tuesday' ELSE '' END
                     + CASE WHEN sch.freq_interval & 8 = 8 THEN ', Wednesday' ELSE '' END
                     + CASE WHEN sch.freq_interval & 16 = 16 THEN ', Thursday' ELSE '' END
                     + CASE WHEN sch.freq_interval & 32 = 32 THEN ', Friday' ELSE '' END
                     + CASE WHEN sch.freq_interval & 64 = 64 THEN ', Saturday' ELSE '' END, 1, 2, '')
               WHEN 16 THEN 'Day ' + CONVERT(varchar, sch.freq_interval) + ' of every '
                   + CONVERT(varchar, sch.freq_recurrence_factor) + ' month(s)'
               WHEN 32 THEN 'The '
                   + CASE sch.freq_relative_interval
                         WHEN 1 THEN 'First'
                         WHEN 2 THEN 'Second'
                         WHEN 4 THEN 'Third'
                         WHEN 8 THEN 'Fourth'
                         WHEN 16 THEN 'Last'
                     END
                   + CASE sch.freq_interval
                         WHEN 1 THEN ' Sunday'
                         WHEN 2 THEN ' Monday'
                         WHEN 3 THEN ' Tuesday'
                         WHEN 4 THEN ' Wednesday'
                         WHEN 5 THEN ' Thursday'
                         WHEN 6 THEN ' Friday'
                         WHEN 7 THEN ' Saturday'
                         WHEN 8 THEN ' Day'
                         WHEN 9 THEN ' Weekday'
                         WHEN 10 THEN ' Weekend Day'
                     END
                   + ' of every ' + CONVERT(varchar, sch.freq_recurrence_factor) + ' month(s)'
               ELSE ''
           END AS occurs_detail,
           CASE sch.freq_subday_type
               WHEN 1 THEN 'Once at ' + CONVERT(varchar(8), DATEADD(second, sch.active_start_time, 0), 108)
               WHEN 2 THEN 'Every ' + CONVERT(varchar, sch.freq_subday_interval) + ' second(s)'
               WHEN 4 THEN 'Every ' + CONVERT(varchar, sch.freq_subday_interval) + ' minute(s)'
               WHEN 8 THEN 'Every ' + CONVERT(varchar, sch.freq_subday_interval) + ' hour(s)'
               ELSE ''
           END AS frequency,
           CONVERT(decimal(10, 2), hist.avg_duration_sec) AS avg_duration_sec,
           CONVERT(decimal(10, 2), hist.max_duration_sec) AS max_duration_sec,
           CASE js.next_run_date
               WHEN 0 THEN NULL
               ELSE msdb.dbo.agent_datetime(js.next_run_date, js.next_run_time)
           END AS next_run
    FROM msdb.dbo.sysjobs AS j
    LEFT JOIN msdb.dbo.sysjobschedules AS js
        ON j.job_id = js.job_id
    LEFT JOIN msdb.dbo.sysschedules AS sch
        ON js.schedule_id = sch.schedule_id
    INNER JOIN msdb.dbo.syscategories AS cat
        ON j.category_id = cat.category_id
    LEFT JOIN (
        SELECT job_id,
               AVG(DATEDIFF(second, 0,
                   STUFF(STUFF(RIGHT('000000' + CONVERT(varchar(6), run_duration), 6), 5, 0, ':'), 3, 0, ':'))
                   * 1.0) AS avg_duration_sec,
               MAX(DATEDIFF(second, 0,
                   STUFF(STUFF(RIGHT('000000' + CONVERT(varchar(6), run_duration), 6), 5, 0, ':'), 3, 0, ':'))
                   * 1.0) AS max_duration_sec
        FROM msdb.dbo.sysjobhistory
        WHERE step_id = 0
        GROUP BY job_id
    ) AS hist
        ON hist.job_id = j.job_id
) AS x
WHERE schedule_enabled = 'Yes'
  AND job_enabled = 'Yes'
  AND avg_duration_sec > @MinAvgDurationSec
ORDER BY next_run;
GO

-- Maintenance plan run logs, newest first (separate from Agent job history).
-- Plan-level rows, then per-task detail for the last few runs.
SELECT TOP (200) * FROM msdb.dbo.sysmaintplan_log ORDER BY start_time DESC;
SELECT TOP (200) * FROM msdb.dbo.sysmaintplan_logdetail ORDER BY start_time DESC;
GO

-- Agent proxies and the credential each maps to.
-- Inventory before adding a proxy or troubleshooting a CmdExec/PowerShell step.
SELECT sp.name AS proxy_name,
       c.name AS credential_name,
       sp.description AS proxy_description
FROM msdb.dbo.sysproxies AS sp
INNER JOIN sys.credentials AS c
    ON sp.credential_id = c.credential_id
ORDER BY sp.name;
GO

-- Which proxy each job step runs under (N/A means the Agent service account).
-- Pairs with the proxy inventory to see who actually executes each step.
SELECT j.name AS job_name,
       s.step_id,
       s.step_name,
       s.subsystem,
       COALESCE(sp.name, 'N/A') AS proxy_name
FROM msdb.dbo.sysjobs AS j
INNER JOIN msdb.dbo.sysjobsteps AS s
    ON j.job_id = s.job_id
LEFT JOIN msdb.dbo.sysproxies AS sp
    ON s.proxy_id = sp.proxy_id
ORDER BY j.name, s.step_id;
GO

-- Start a job on demand. Replace the placeholder with the real job name.
-- Returns immediately; the job runs asynchronously.
EXEC msdb.dbo.sp_start_job @job_name = N'<JobName>';
GO

-- Destructive: disables every enabled job. Generate-and-print by default.
-- @WhatIf = 1 prints the statements; set to 0 to actually disable.
-- Useful before maintenance or a controlled failover. Re-enable individually after.
DECLARE @WhatIf bit = 1;
DECLARE @sql nvarchar(max);

SELECT @sql = STRING_AGG(
        CAST(N'EXEC msdb.dbo.sp_update_job @job_name = N'
             + QUOTENAME(name, '''') + N', @enabled = 0;' AS nvarchar(max)),
        CHAR(13) + CHAR(10))
FROM msdb.dbo.sysjobs
WHERE enabled = 1;

IF @sql IS NULL
    PRINT 'No enabled jobs.';
ELSE IF @WhatIf = 1
    PRINT @sql;
ELSE
    EXEC sys.sp_executesql @sql;
GO

-- Job ownership review and fix live in security/ownership.sql (do not duplicate here).

-- Reference - Agent proxy/credential system views in msdb:
--   sysproxies             one row per proxy
--   sysproxylogin          logins mapped to each proxy (sysadmin members not listed)
--   sysproxysubsystem      subsystems enabled for each proxy
--   syssubsystems          available Agent proxy subsystems

-- Reference - msdb Agent fixed database roles (sysadmin can administer everything):
--   SQLAgentUserRole       manage jobs/schedules they own
--   SQLAgentReaderRole     UserRole plus view all jobs and schedules
--   SQLAgentOperatorRole   manage local jobs, view operators/proxies/alerts
