/*
-- Fix inaccessible SQL Server instance when no one remembers the sa password.

C:\Windows\system32>net start MSSQLSERVER /mSQLCMD
The SQL Server (MSSQLSERVER) service is starting.
The SQL Server (MSSQLSERVER) service was started successfully.

C:\Windows\system32>sqlcmd -S. -E
1> CREATE LOGIN [domain\username] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [domain\username];
2> go

*/
