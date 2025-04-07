
/**********************************************************************************************/
-- total_physical_memory            - the total amount of non-virtual memory available to the OS
-- available_physical_memory        - the amount of non-virtual memory currently available to the OS
-- total_page_file                  - the current size of the OS's virtual memory/page file
-- available_page_file              - the amount of virtual memory currently available to the OS
-- system_memory_state_desc         - indicates if available memory is high, low, steady,
--                                    or transitioning from one state to another
/**********************************************************************************************/
-- physical_memory_in_use           - all physical memory in use on the server by the SQL processes
-- virtual_address_space_committed  - amount of virtual address space committed to the SQL Server process
-- virtual_address_space_available  - amount of virtual address space that is committed but not currently in use
-- page_fault_count                 - number of times data needed was not found in process memory,
--                                    causing a physical read to disk
-- process_physical_memory_low      - when the SQL Server process is needing more RAM than is physically available,
--                                    this value is set to 1
-- process_virtual_memory_low       - when the SQL Server process is needing more virtual RAM than is currently available,
--                                    this value is set to 1.
/**********************************************************************************************/
-- Buffer cache hit ratio:
-- 		How often SQL Server is able to find data pages in its buffer cache when a query needs a data page.
-- 		The higher this number the better, because it means SQL Server was able to get data for
-- 		queries out of memory instead of reading from disk.
-- 		You want this number to be as close to 100 as possible.
-- 		Having this counter at 100 means that 100% of the time SQL Server has found the needed data pages in memory.
-- 		A low buffer cache hit ratio could indicate a memory problem.
--
-- Buffer cache hit ratio base:
-- 	    Base value - divisor to calculate the hit ratio percentage
--
-- Page life expectancy:
-- 		How long pages stay in the buffer cache in seconds.
-- 		The longer a page stays in memory, the more likely server will not need to read from HDD to resolve a query.
-- 		Some say anything below 300 (or 5 minutes) means you might need additional memory.
/**********************************************************************************************/

SELECT total_physical_memory_kb /1024 AS total_physical_memory_MB ,
available_physical_memory_kb /1024 AS available_physical_memory_MB ,
total_page_file_kb /1024 AS total_page_file_MB ,
available_page_file_kb /1024 AS available_page_file_MB, system_memory_state_desc
FROM sys.dm_os_sys_memory


SELECT physical_memory_in_use_kb /1024 AS physical_memory_in_use_MB,
virtual_address_space_committed_kb /1024 AS virtual_address_space_committed_MB,
virtual_address_space_available_kb /1024 AS virtual_address_space_available_MB,
page_fault_count, process_physical_memory_low, process_virtual_memory_low
FROM sys.dm_os_process_memory

SELECT [counter_name] = RTRIM([counter_name]), [cntr_value], [instance_name] 
FROM sys.dm_os_performance_counters
WHERE [counter_name] IN ( 'Page life expectancy', 'Buffer cache hit ratio', 'Buffer cache hit ratio base' )
AND [object_name] NOT LIKE '%Partition%' 
AND [object_name] NOT LIKE '%Node%'

/**********************************************************************************************/
-- Ring-buffer memory-related usage
SELECT 
    EventTime,
    record.value('(/Record/ResourceMonitor/Notification)[1]', 'varchar(max)') as [Type],
    record.value('(/Record/ResourceMonitor/IndicatorsProcess)[1]', 'int') as [IndicatorsProcess],
    record.value('(/Record/ResourceMonitor/IndicatorsSystem)[1]', 'int') as [IndicatorsSystem],
    record.value('(/Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint') AS [Avail Phys Mem, Kb],
    record.value('(/Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint') AS [Avail VAS, Kb]
FROM (
    SELECT
        DATEADD (ss, (-1 * ((cpu_ticks / CONVERT (float, ( cpu_ticks / ms_ticks ))) - [timestamp])/1000), GETDATE()) AS EventTime,
        CONVERT (xml, record) AS record
    FROM sys.dm_os_ring_buffers
    CROSS JOIN sys.dm_os_sys_info
    WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR') AS tab
ORDER BY EventTime DESC;