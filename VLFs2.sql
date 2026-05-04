/**********************************************************************************************/
/* Number of VLF files per database (> 1000 VLF may be an issue, > 10000 certainly is) */
DECLARE @databaseList TABLE
(
      [database]        VARCHAR(256),
      [executionOrder]  INT IDENTITY(1,1) NOT NULL
)
 
DECLARE @vlfDensity     TABLE
(
      [server]          VARCHAR(256),
      [database]        VARCHAR(256),
      [density]         DECIMAL(7,2),
      [unusedVLF]       INT,
      [usedVLF]         INT,
      [totalVLF]        INT
)
 
DECLARE @logInfoResult TABLE
(
      [FileId]      INT NULL,
      [FileSize]    BIGINT NULL,
      [StartOffset] BIGINT NULL,
      [FSeqNo]      INT NULL,
      [Status]      INT NULL,
      [Parity]      TINYINT NULL,
      [CreateLSN]   NUMERIC(25, 0) NULL
)
 
DECLARE
    @currentDatabaseID      INT,
    @maxDatabaseID          INT,
    @dbName                 VARCHAR(256),
    @density                DECIMAL(7,2),
    @unusedVLF              INT,
    @usedVLF                INT,
    @totalVLF               INT
 
INSERT INTO @databaseList   ([database] )
SELECT [name]
FROM [sys].[sysdatabases]
 
SELECT @currentDatabaseID = MIN([executionOrder]), @maxDatabaseID = MAX([executionOrder])
FROM @databaseList

WHILE @currentDatabaseID <= @maxDatabaseID
      BEGIN
            SELECT @dbName = [database] FROM @databaseList WHERE [executionOrder] = @currentDatabaseID
            DELETE @logInfoResult FROM @logInfoResult
 
            INSERT INTO @logInfoResult EXEC('DBCC LOGINFO([' + @dbName + '])')
 
            SELECT @unusedVLF = COUNT(*) FROM @logInfoResult WHERE [Status] = 0
            SELECT @usedVLF = COUNT(*) FROM @logInfoResult WHERE [Status] = 2
            SELECT @totalVLF = COUNT(*) FROM @logInfoResult
            SELECT @density = CONVERT(DECIMAL(7,2),@usedVLF) / CONVERT(DECIMAL(7,2),@totalVLF) * 100
 
            INSERT INTO @vlfDensity ([server],[database],[density],[unusedVLF],[usedVLF],[totalVLF])
            VALUES (@@SERVERNAME,@dbName,@density,@unusedVLF,@usedVLF,@totalVLF)
 
            SET @currentDatabaseID = @currentDatabaseID + 1
      END
 SELECT
    [server],[database],[density],[unusedVLF],[usedVLF], [totalVLF]
FROM @vlfDensity
      WHERE totalVLF >1000
ORDER BY totalVLF DESC