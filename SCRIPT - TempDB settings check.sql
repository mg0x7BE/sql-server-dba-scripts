/**********************************************************************************************/
/*
	CMS-friendly script to check TempDB settings

	Version: 1.0
	Modified: 5/29/2013
		
	script requires xp_cmdshell to be enabled 
*/

DECLARE @max_size VARCHAR(max) 
SELECT @max_size = COALESCE(CONVERT(nvarchar(100),@max_size) + '  ', '') + CONVERT(nvarchar(100),(max_size*8)/1024)
from sys.master_files where database_id = 2 and type = 0 order by file_id

DECLARE @size VARCHAR(max) 
SELECT @size = COALESCE(CONVERT(nvarchar(100),@size) + '  ', '') + CONVERT(nvarchar(100),(size*8)/1024)
from sys.master_files where database_id = 2 and type = 0 order by file_id

DECLARE @growth VARCHAR(max) 
SELECT @growth = COALESCE(CONVERT(nvarchar(100),@growth) + '  ', '') + CASE WHEN is_percent_growth = 1 THEN '%' ELSE CONVERT(nvarchar(100),(growth*8)/1024) END
from sys.master_files where database_id = 2 and type = 0 order by file_id

DECLARE @is_percent_growth VARCHAR(max) 
SELECT @is_percent_growth = COALESCE(CONVERT(nvarchar(100),@is_percent_growth) + '  ', '') + CONVERT(nvarchar(100),is_percent_growth)
from sys.master_files where database_id = 2 and type = 0 order by file_id

DECLARE @LUN sysname
SET @LUN = (select SUBSTRING(physical_name, 1, CHARINDEX('\', physical_name, 4))
from sys.master_files where database_id = 2 and file_id = 1)

DECLARE @log_growth varchar(100)
SELECT @log_growth = CASE WHEN is_percent_growth = 1 THEN '%' ELSE CONVERT(nvarchar(100),(growth*8)/1024) END
from sys.master_files where database_id = 2 and type = 1

DECLARE @is_log_percent_growth bit
SELECT @is_log_percent_growth = is_percent_growth
from sys.master_files where database_id = 2 and type = 1

DECLARE @dedicated bit
SET @dedicated = (SELECT CASE WHEN (@LUN like '%tempdb%') THEN 1 ELSE 0 END)

DECLARE @cmd sysname
SET @cmd = 'fsutil volume diskfree ' + @LUN + ' |find "Total # of bytes"'
DECLARE @Output TABLE
(
	Output nvarchar(max)
)
INSERT INTO @Output
EXEC xp_cmdshell @cmd

SELECT
	@LUN as 'LUN',
	GB,
	@dedicated as 'Dedicated',
		CASE WHEN @dedicated = 1 THEN
			CAST(FLOOR((((GB * 1024) * .8) / 8)) as NVARCHAR(30))
		ELSE
			CAST(FLOOR(((((GB - 10) * 1024) * .7) / 8)) as NVARCHAR(30)) 
		END as 'standard size MB',
	@size as 'actual size MB',
	@max_size as 'max size MB', 
	@growth as 'growth MB',
	@is_percent_growth 'is percent growth',
	@log_growth as 'log growth MB',
	@is_log_percent_growth as 'is log percent growth'
FROM
(
	SELECT @LUN as 'LUN', CONVERT(bigint,REPLACE([Output], 'Total # of bytes             : ', '' )) / 1073698000 as 'GB'
	FROM @Output 
	WHERE [Output] IS NOT NULL
) as x

/**********************************************************************************************/

