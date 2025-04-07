/**********************************************************************************************/
-- to enable system extended stored procedures that are used for Database Mail
-- either run the Database Mail Configuration Wizards, 
-- or set the sp_configure option "Database Mail XPs" to the value 1

EXEC msdb.dbo.sp_send_dbmail
	@profile_name = 'Proseware Administrator',
	@recipients = 'admin@AdventureWorks.com',
	@body = 'Daily backup completed successsfully.',
	@subject = 'Daily backup status';

/**********************************************************************************************/
-- retention policy needs to be planned to limit msdb growth
-- delete messages, attachments, and log entries that are more than one month old
USE msdb;
GO

DECLARE @CutoffDate datetime;
SET @CutoffDate = DATEADD(m, -1, SYSDATETIME());

EXECUTE dbo.sysmail_delete_mailitems_sp
	@sent_before = @CutoffDate;

EXECUTE dbo.sysmail_delete_log_sp
	@logged_before = @CutoffDate;
GO

/**********************************************************************************************/
-- track the delivery status of an individual messages
dbo.sysmail_allitems
dbo.sysmail_sentitems
dbo.sysmail_unsentitems
dbo.sysmail_faileditems
dbo.sysmail_mailattachments

/**********************************************************************************************/
-- Query the database mail event log

SELECT * FROM msdb.dbo.sysmail_event_log;
GO

/**********************************************************************************************/
-- Query the database mail outgoing mail log

SELECT * FROM msdb.dbo.sysmail_mailitems;
GO

/**********************************************************************************************/