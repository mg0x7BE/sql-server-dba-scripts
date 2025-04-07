/**********************************************************************************************/
--	DMVs and DMFs
/*

		sys.dm_exec_%  -- Execution and Connection

		These objects provide information about connections, sessions, requests, and query execution.
		For example, sys.dm_exec_sessions provides on row for every session that is currently connected to the server.

		sys.dm_os_%    -- SQL OS related information

		These objects provide access to SQL OS related information.
		For example, sys.dm_os_performance_counters provides access to SQL Server performance counters
		without the need to access them using operating system tools.

		sys.dm_tran_%  -- Transaction Management

		These objects provide access to transaction management.
		For example, sys.dm_os_tran_active_transactions provides details of currently active transactions

		sys.dm_io_%    -- I/O related information

		These objects provide information on I/O processes.
		For example, sys.dm_io_virtual_file_stats provides details of I/O performance and statistics for each database file.

		sys.dm_db_%    -- Database scoped information

		These objects provide database-scoped information.
		For example, sys.dm_db_index_usage_stats provides information about how each index in the database has been used.

*/