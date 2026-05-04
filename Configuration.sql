/**********************************************************************************************/
-- check system configuration
select * from sys.configurations order by name

/**********************************************************************************************/
-- list all configuration options
USE master;
go
EXEC sp_configure 'show advanced option', '1';

/**********************************************************************************************/
-- run the RECONFIGURE statement
reconfigure
go

/**********************************************************************************************/
-- adjusting memory allocation and MAXDOP
exec sp_configure 'max server memory', 12288
go
exec sp_configure 'max degree of parallelism', 4
go
reconfigure
go

/**********************************************************************************************/
