/**********************************************************************************************/
-- Returns the table the error is against

use distribution
GO

select * from dbo.MSarticles where article_id in 
( 
	select article_id from MSrepl_commands 
	where xact_seqno = 0x0003BB0E000001DF000600000000
)

-- returns the command (and the primary key (ie the row) the command was executing against)

exec sp_browsereplcmds @xact_seqno_start = '0x0003BB0E000001DF000600000000',
					     @xact_seqno_end = '0x0003BB0E000001DF000600000000'

/**********************************************************************************************/
--	To prevent issues with replication such as 
--	Cannot insert explicit value for identity column in table <...> when IDENTITY_INSERT is set to OFF
--	This is typical where the database was created off a database that did not have the publication
--	created on it when the copy was made. To ensure the articles / tables in the new databases have their
--	identity columns flagged correctly run the following:

EXEC sp_msforeachtable @command1 = '
declare @int int
set @int =object_id("?")
EXEC sys.sp_identitycolumnforreplication @int, 1'

/**********************************************************************************************/