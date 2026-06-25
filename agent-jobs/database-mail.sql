/*
    Agent jobs / Database Mail
    Database Mail: send, status logs, and retention cleanup.
*/

-- Classic Database Mail is box/IaaS only; Azure SQL DB / Managed Instance use their own mail path.
-- Requires the "Database Mail XPs" config option set to 1 (run the wizard or sp_configure).

-- Send a test message. Use to confirm a profile delivers and as a job step on success/failure.
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'YourMailProfile',
    @recipients   = 'dba@yourcompany.com',
    @subject      = 'Daily backup status',
    @body         = 'Daily backup completed successfully.';
GO

-- Per-item delivery status. Check after a send, or when a recipient reports a missing mail.
USE msdb;
GO
SELECT * FROM dbo.sysmail_allitems     ORDER BY send_request_date DESC;
SELECT * FROM dbo.sysmail_sentitems    ORDER BY send_request_date DESC;
SELECT * FROM dbo.sysmail_unsentitems  ORDER BY send_request_date DESC;
SELECT * FROM dbo.sysmail_faileditems  ORDER BY send_request_date DESC;
SELECT * FROM dbo.sysmail_mailattachments;
GO

-- Outgoing mail log (full mailitems table). Use to inspect body/recipients of a specific message.
SELECT * FROM msdb.dbo.sysmail_mailitems ORDER BY send_request_date DESC;
GO

-- Database Mail event log. First stop when mail is stuck or failing; shows the actual error text.
SELECT * FROM msdb.dbo.sysmail_event_log ORDER BY log_date DESC;
GO

-- Retention cleanup to limit msdb growth. Deletes mail items, attachments, and log entries
-- older than the retention window. Destructive: set @Execute = 1 to run; default is no-op.
USE msdb;
GO
DECLARE @RetentionMonths int = 1;            -- placeholder: keep this many months
DECLARE @Execute bit = 0;                    -- safety gate: 1 to perform the deletes
DECLARE @CutoffDate datetime = DATEADD(MONTH, -@RetentionMonths, SYSDATETIME());

IF @Execute = 1
BEGIN
    EXECUTE msdb.dbo.sysmail_delete_mailitems_sp
        @sent_before = @CutoffDate;

    EXECUTE msdb.dbo.sysmail_delete_log_sp
        @logged_before = @CutoffDate;
END
ELSE
    PRINT 'Retention cleanup skipped: set @Execute = 1 to delete items before ' + CONVERT(varchar(30), @CutoffDate, 121);
GO
