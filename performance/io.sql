/*
    Performance / I/O
    File level I/O latency and throughput from sys.dm_io_virtual_file_stats.
*/

-- Per file I/O latency and throughput, worst latency first.
-- Counters are cumulative since instance startup; rerun and diff for a live picture.
SELECT
    DB_NAME(fs.database_id) AS database_name,
    mf.name AS logical_name,
    mf.type_desc,
    mf.physical_name,
    fs.num_of_reads,
    fs.num_of_writes,
    fs.num_of_bytes_read,
    fs.num_of_bytes_written,
    fs.io_stall_read_ms,
    fs.io_stall_write_ms,
    fs.io_stall,
    avg_read_latency_ms  = fs.io_stall_read_ms  / NULLIF(fs.num_of_reads, 0),
    avg_write_latency_ms = fs.io_stall_write_ms / NULLIF(fs.num_of_writes, 0),
    avg_latency_ms       = fs.io_stall / NULLIF(fs.num_of_reads + fs.num_of_writes, 0)
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
LEFT JOIN sys.master_files AS mf
    ON mf.database_id = fs.database_id
   AND mf.file_id = fs.file_id
ORDER BY avg_latency_ms DESC;

-- Per database rollup of the same counters.
-- Quick way to spot which database is driving disk pressure.
SELECT
    DB_NAME(fs.database_id) AS database_name,
    SUM(fs.num_of_reads) AS num_of_reads,
    SUM(fs.num_of_writes) AS num_of_writes,
    SUM(fs.num_of_bytes_read) AS num_of_bytes_read,
    SUM(fs.num_of_bytes_written) AS num_of_bytes_written,
    SUM(fs.io_stall_read_ms) AS io_stall_read_ms,
    SUM(fs.io_stall_write_ms) AS io_stall_write_ms,
    SUM(fs.io_stall) AS io_stall,
    avg_read_latency_ms  = SUM(fs.io_stall_read_ms)  / NULLIF(SUM(fs.num_of_reads), 0),
    avg_write_latency_ms = SUM(fs.io_stall_write_ms) / NULLIF(SUM(fs.num_of_writes), 0),
    avg_latency_ms       = SUM(fs.io_stall) / NULLIF(SUM(fs.num_of_reads) + SUM(fs.num_of_writes), 0)
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
GROUP BY fs.database_id
ORDER BY avg_latency_ms DESC;
