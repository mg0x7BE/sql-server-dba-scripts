/**********************************************************************************************/
-- shows the backup progress

SELECT session_id as SPID, command, a.text AS Query, start_time, percent_complete, dateadd(second,estimated_completion_time/1000, getdate()) as estimated_completion_time 
FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) a 
WHERE r.command in ('BACKUP DATABASE','RESTORE DATABASE')

/**********************************************************************************************/
-- view the backup history

SELECT 
	bs.media_set_id,
	bs.backup_finish_date,
	bs.type,
	bs.backup_size,
	bs.compressed_backup_size,
	mf.physical_device_name
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS mf
ON bs.media_set_id = mf.media_set_id -- WHERE database_name = 'AdventureWorks2008R2'
ORDER BY backup_finish_date DESC;
GO

/**********************************************************************************************/
-- are there any backups taken in the last 24 hours?

SELECT
	db.name,
	bs.backup_finish_date,
	bs.type
FROM 
	master.sys.databases db
LEFT JOIN
	msdb.dbo.backupset AS bs
ON 
	db.name = bs.database_name
AND 
	backup_finish_date BETWEEN DATEADD(dd, -1, DATEDIFF(dd, 0, GETDATE())) 
						   AND DATEADD(dd,  0, DATEDIFF(dd, 0, GETDATE()))
WHERE 
	db.name NOT IN ('msdb','model','master','distribution','tempdb') 
ORDER BY 
	backup_finish_date DESC;
GO

/**********************************************************************************************/
-- when was the last backup?

SELECT d.name, MAX(b.backup_finish_date) AS last_backup_finish_date
FROM master.sys.databases d
LEFT OUTER JOIN msdb.dbo.backupset b ON d.name = b.database_name AND b.type = 'D'
WHERE d.database_id NOT IN (2, 3) 
GROUP BY d.name
ORDER BY 2 DESC

/**********************************************************************************************/

