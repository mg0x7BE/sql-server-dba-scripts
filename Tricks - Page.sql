/**********************************************************************************************/
-- Display data from the specific page

-- (12:169272:0)
-- (data file 12, page 169272, record 0)
SELECT
	sys.fn_PhysLocFormatter(%%physloc%%), * 
FROM 
	[AdventureWorks2012].[Person].[Person]

-- find database_id
SELECT
	*
from
	sys.databases

-- find database_id
select DB_ID('AdventureWorks2012') 

-- find database name
select DB_NAME(8)


DBCC TRACESTATUS (-1)   -- shows all trace settings applying to the connection

DBCC TRACESTATUS (3604) -- shows trace settings for 3604 flag

DBCC TRACEON(3604)      -- shows hidden output for DBCC PAGE

-- DBCC PAGE(database_id, data file, page, output)
-- output 1, 2 or 3, where 3 shows all the data
DBCC PAGE (8,1,1472,3)

/**********************************************************************************************/