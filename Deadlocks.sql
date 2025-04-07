/**********************************************************************************************/
-- Show all trace flags
DBCC TRACESTATUS

/**********************************************************************************************/
-- Two trace flags can be enabled to capture more information in the log: 1204 and 1222. 
-- 1204 lists the information by node; 1222 lists it by process and resource. 
-- You can enable both simultaneously. To enable the flags, use the command
DBCC TRACEON (1204, 1222)