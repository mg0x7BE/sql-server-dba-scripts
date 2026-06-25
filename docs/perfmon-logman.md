# Perfmon and logman

OS level performance collection with logman and Perfmon counters.

## Counter object names

- Default instance: `\SQLServer:<object>\<counter>`
- Named instance: `\MSSQL$<InstanceName>:<object>\<counter>`

Swap the prefix everywhere below when targeting a named instance. The OS counters (`\Memory`, `\Process`, `\PhysicalDisk`) do not change.

## Memory counters

Collects OS memory, the sqlservr process footprint, and the SQL Server buffer/memory managers at a 5 second interval.

```cmd
logman create counter "Memory Counters" -si 05 -v nnnnnn -o "C:\PerfLogs\Memory Counters" ^
  -c "\Memory\Available MBytes" ^
     "\Process(sqlservr)\Virtual Bytes" ^
     "\Process(sqlservr)\Working Set" ^
     "\Process(sqlservr)\Private Bytes" ^
     "\SQLServer:Buffer Manager\Database pages" ^
     "\SQLServer:Buffer Manager\Target pages" ^
     "\SQLServer:Buffer Manager\Total pages" ^
     "\SQLServer:Memory Manager\Target Server Memory (KB)" ^
     "\SQLServer:Memory Manager\Total Server Memory (KB)"
```

## I/O counters

Per physical disk latency, throughput, and queue lengths.

```cmd
logman create counter "IO Counters" -si 05 -v nnnnnn -o "C:\PerfLogs\IO Counters" ^
  -c "\PhysicalDisk(*)\Avg. Disk Bytes/Read" ^
     "\PhysicalDisk(*)\Avg. Disk Bytes/Write" ^
     "\PhysicalDisk(*)\Avg. Disk Read Queue Length" ^
     "\PhysicalDisk(*)\Avg. Disk sec/Read" ^
     "\PhysicalDisk(*)\Avg. Disk sec/Write" ^
     "\PhysicalDisk(*)\Avg. Disk Write Queue Length" ^
     "\PhysicalDisk(*)\Disk Read Bytes/sec" ^
     "\PhysicalDisk(*)\Disk Reads/sec" ^
     "\PhysicalDisk(*)\Disk Write Bytes/sec" ^
     "\PhysicalDisk(*)\Disk Writes/sec"
```

## Named instance example

For an instance named `SQL01`, prefix the SQL counters with `\MSSQL$SQL01:`.

```cmd
logman create counter "Memory Counters SQL01" -si 05 -v nnnnnn -o "C:\PerfLogs\Memory Counters SQL01" ^
  -c "\MSSQL$SQL01:Buffer Manager\Total pages" ^
     "\MSSQL$SQL01:Memory Manager\Total Server Memory (KB)"
```

## Run a collection

```cmd
REM inspect a defined collector
logman query "IO Counters"

REM start, let it run, stop
logman start "Memory Counters"
timeout /t 5
REM do the work you want to capture here
logman stop "Memory Counters"
timeout /t 5
```

`-o` writes a binary `.blg` to the given path; the `-v nnnnnn` token appends an incrementing serial so each run gets its own file. Open the `.blg` in Perfmon or import with `relog` for analysis.

## In-engine alternatives

Inside SQL Server, use `sys.dm_os_performance_counters`, Extended Events, or Query Store instead of OS level collection.

```sql
SELECT object_name, counter_name, instance_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name IN (N'Total Server Memory (KB)', N'Target Server Memory (KB)');
```
