/**********************************************************************************************/
-- Space used by all databases and files

Create TABLE #db_file_information( 
fileid integer
, theFileGroup integer
, Total_Extents integer
, Used_Extents integer
, db varchar(30)
, file_Path_name varchar(300))

-- Get the size of the datafiles
insert into #db_file_information 
( fileid 
, theFileGroup 
, Total_Extents 
, Used_Extents 
, db 
, file_Path_name )
exec sp_MSForEachDB 'Use ?; DBCC showfilestats'

-- add two columns to the temp table
alter table #db_file_information add PercentFree as 
((Total_Extents-Used_Extents)*100/(Total_extents))

alter table #db_file_information add TotalSpace_MB as 
((Total_Extents*64)/1024)

alter table #db_file_information add UsedSpace_MB as 
((Used_Extents*64)/1024)

alter table #db_file_information add FreeSpace_MB as 
((Total_Extents*64)/1024-(Used_Extents*64)/1024)

select * from #db_file_information

drop table #db_file_information

/**********************************************************************************************/