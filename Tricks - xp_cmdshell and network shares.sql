/**********************************************************************************************/
-- map network share over xp_cmdshell

EXEC xp_cmdshell 'dir *.exe';

net use t: \\10.216.224.25\shared password123 /USER:builtin\dbbackup

net use t: /delete

/**********************************************************************************************/
