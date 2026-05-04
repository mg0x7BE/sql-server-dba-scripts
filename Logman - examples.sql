/**********************************************************************************************/

Logman create counter "Memory Counters" -si 05 -v nnnnnn -o "c:\perflogs\Memory Counters" -c "\Memory\Available MBytes" "\Process(sqlservr)\Virtual Bytes" "\Process(sqlservr)\Working Set" "\Process(sqlservr)\Private Bytes" "\SQLServer:Buffer Manager\Database pages" "\SQLServer:Buffer Manager\Target pages" "\SQLServer:Buffer Manager\Total pages" "\SQLServer:Memory Manager\Target Server Memory (KB)" "\SQLServer:Memory Manager\Total Server Memory (KB)"

/**********************************************************************************************/

Logman create counter "IO Counters" -si 05 -v nnnnnn -o "c:\perflogs\IO Counters" -c "\PhysicalDisk(*)\Avg. Disk Bytes/Read" " \PhysicalDisk(*)\Avg. Disk Bytes/Write" "\PhysicalDisk(*)\Avg. Disk Read Queue Length" "\PhysicalDisk(*)\Avg. Disk sec/Read" "\PhysicalDisk(*)\Avg. Disk sec/Write" "\PhysicalDisk(*)\Avg. Disk Write Queue Length" "\PhysicalDisk(*)\Disk Read Bytes/sec" "\PhysicalDisk(*)\Disk Reads/sec" "\PhysicalDisk(*)\Disk Write Bytes/sec" "\PhysicalDisk(*)\Disk Writes/sec"

/**********************************************************************************************/

logman query "IO Counters"

/**********************************************************************************************/

REM start counter collection
logman start "Memory Counters"
timeout /t 5
REM add a timeout for some short period
REM to allow the collection to start
REM do something interesting here

REM stop the counter collection
logman stop "Memory Counters"
timeout /t 5
REM make sure to wait 5 to ensure its stopped

/**********************************************************************************************/