/**********************************************************************************************/
/*
-----------------------------------------------------------------------------------------
model
Template for all databases
Restore: Start instance with the -T3608 trace flag (only starts the master). Next, the model database can be restored using the normal RESTORE DATABASE command.
-----------------------------------------------------------------------------------------
msdb
Used by SQL Server Agent for scheduling alerts and jobs, and for recording details of operations. Also contains history tables. If corrupt, SQL Server Agent will not start.
Restore: Like any user database using the RESTORE DATABASE command.
-----------------------------------------------------------------------------------------
resource
Read-only db that contains copies of all system objects
Restore: file-level restore in Windows or by running the setup program for SQL Server.
-----------------------------------------------------------------------------------------
tempdb
Workspace for holding temporary or intermediate result sets.
No backup operations can be performed.
Restore: re-created every time an instance of SQL Server is started. 
-----------------------------------------------------------------------------------------
master
Holds all system level configurations
Restore: Single User Mode

1) some version of a master database must exist so that the SQL Server instance will start at all. Use temporary master database if needed:

- use SQL Server setup (may be found at path similar to ~ SQL Server\110\Setup\Bootstrap\SQL11\setup.exe). Please note that the setup program will overwrite all system DBs.

- obtain file-level backup of the master database (either taken when SQL Server was offline, or by VSS service)

- locate a master.mdf database from the Templates folder located in the MSSQL\Binn folder for each instance

2) Once a temporary master database has been put in place, use the following procedure to recover the correct master database:

- start the server instance in single-user mode (-m startup option)

- use RESTORE DATABASE to restore a full database backup of a master (recommended via sqlcmd utility)

- after the master is restored, the instance of SQL Server will shut down

- remove the single-user parameter

- restart SQL server

*/
/**********************************************************************************************/
