/**********************************************************************************************/
/*
  Catalog Views
*/
select * from sys.service_message_types
select * from sys.service_contracts
select * from sys.service_contract_message_usages
select * from sys.service_queues

/**********************************************************************************************/
/*
  Contract details
*/
SELECT
	 c.name AS 'Contract'
	,mt.name AS 'Message Name'
	,cmu.is_sent_by_initiator
	,cmu.is_sent_by_target
	,mt.validation_desc
FROM
	sys.service_contract_message_usages cmu
JOIN
	sys.service_message_types mt
ON
	mt.message_type_id = cmu.message_type_id
JOIN
	sys.service_contracts c
ON
	c.service_contract_id = cmu.service_contract_id
ORDER BY 1,2

/**********************************************************************************************/
/*
  Names of services and their associated contracts
*/
SELECT
	 s.name as 'Service'
	,c.name as 'Contract'
FROM
	sys.services s
JOIN
	sys.service_contract_usages cu
ON
	cu.service_id = s.service_id
JOIN
	sys.service_contracts c
ON
	c.service_contract_id = cu.service_contract_id
ORDER BY 1,2

/**********************************************************************************************/

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'password'

OPEN MASTER KEY DECRYPTION BY PASSWORD = 'password'

-- enable Service Broker:
ALTER DATABASE sample_database
    SET ENABLE_BROKER

-- show DBs with service broker enabled:
select
    is_broker_enabled,
    service_broker_guid,
    *
from
    sys.databases s
where is_broker_enabled = 1

/**********************************************************************************************/
-- Message Types
-- Message types validate that the data within a message is the correct, expected format.

-- Validation types
/*
	NONE
	EMPTY
	WELL_FORMED_XML
	VALID_XML WITH SCHEMA COLLECTION
		(???) ---> CREATE XML SCHEMA COLLECTION
*/

-- Creation of a message type
CREATE MESSAGE TYPE YourMessageType
    AUTHORIZATION dbo							-- owner of the message type
    VALIDATION = WELL_FORMED_XML

/**********************************************************************************************/
-- Contracts
-- Contracts define the message types that are used within a single conversation.

-- User who can use message type
/*
	INITIATIOR   -- The SQL Server Service Broker SERVICE who initiated the conversation
	TARGET       -- The SQL Server Service Broker SERVICE who received the conversation
	ANY          -- Enables both the TARGET and the INITIATOR to use the message type
*/

CREATE CONTRACT MyContract
    AUTHORIZATION dbo
    (YourMessageType SENT BY ANY)

CREATE CONTRACT MyContract
    AUTHORIZATION dbo
    (YourMessageType SENT BY INITIATOR, AnotherMessageType SENT BY TARGET)

/**********************************************************************************************/
-- Queues
-- Queues are where the messages within the SQL Server Service Broker are stored in the time period
-- between when they are sent and when they are processed.
-- Although the rest of the objects created are logical objects made up only of records
-- in system tables, queues are physical objects that create physical tables under them that store the
-- actual messages. Because queues are physical tables, one of the many options available to the person
-- creating the queue is the file group that will contain the queue.

CREATE QUEUE YourQueue_Source
    WITH STATUS=ON,              -- messages can be received from the queue
    RETENTION=OFF,               -- when ON, the messages are not removed from the queue (once recieved)
-- (used for auditing purposes only)
    ACTIVATION  (STATUS=OFF,     -- enable or disable the activation procedure (OFF stops only new threads)
        PROCEDURE_NAME=dbo.MySourceActivationProcedure,  -- stored procedure that should be activated
        MAX_QUEUE_READERS=1,  -- The number of threads that should be spawned, each of
        -- which calls the activated stored procedure.
        EXECUTE AS OWNER),    -- usr the procedure should be run as (SELF, OWNER, or any valid user)
    POISION_MESSAGE_HANDLING=ON; -- causes the queue to automatically disable after
-- five consecutive transaction rollbacks
-- (otherwise the the message handling must be handled within the application)

/*
	Two queues should be used when sending messages within an application:
	one queue as the source queue, and one queue as the destination queue.

	queue is often created without configuring the ACTIVATION settings
	Instead, the stored procedure is created and the queue is
	altered using the ALTER QUEUE command to set the activation settings.
*/

/**********************************************************************************************/
-- Services
-- Services can specify which contracts (and therefore which
-- message types) can be used when sending messages to a specific queue.

CREATE SERVICE YourService_Source
    AUTHORIZATION dbo
    ON QUEUE dbo.YourQueue_Source
    (MyContract)   -- Comma-separated list of contracts
GO

/**********************************************************************************************/
-- Routes
-- Routes control the database to which the messages should be routed.

CREATE ROUTE ExpenseRoute
    WITH SERVICE_NAME = 'MyService',  -- case-sensitive, can be omitted. The name of the service to which the route should apply.
    BROKER_INSTANCE = '53FA2363-BF93-4EB6-A32D-F672339E08ED',  -- tells the route to which database on the server to send the messages
-- guid can be queried from the sys.databases
    ADDRESS = 'TCP://sql2:1234',         -- IP / network name / FQDN / "LOCAL" (same instance) / "TRANSPORT" (tries to identify by service)
    MIRROR_ADDRESS = 'TCP://sql4:4567' ; -- This optional parameter confi gures the route to support database
-- mirroring if the destination database is configured for database mirroring.

/**********************************************************************************************/
-- Priorities
-- SQL Server Service Broker priorities assign priorities to conversations to force specifi c conversations
-- to always be processed before lower priority conversations.

CREATE BROKER PRIORITY HighPriority
    FOR CONVERSATION SET
    (
    CONTRACT_NAME = MyHighPriority ,
    LOCAL_SERVICE_NAME = ANY ,
    REMOTE_SERVICE_NAME = N'ANY' ,
    PRIORITY_LEVEL = 8     -- from 1 to 10
    )

/**********************************************************************************************/
-- Conversation Groups
-- Conversation groups control the order that messages are processed when those messages are sent to
-- different services.

-- query the conversation group that the next message to be processed is a memory of
DECLARE @conversation_group_id AS UNIQUEIDENTIFIER;
GET CONVERSATION GROUP @conversation_group_id
    FROM YourQueue;

/**********************************************************************************************/
-- sending messages

DECLARE @message_body AS XML, @dialog_handle as UNIQUEIDENTIFIER

SET @message_body = (SELECT *
                     FROM sys.all_objects as object
                     FOR XML AUTO, root('root'))

BEGIN DIALOG CONVERSATION @dialog_handle
    FROM SERVICE [YourSourceService]
    TO SERVICE 'YourDestinationService'
    ON CONTRACT [YourContract];

SEND ON CONVERSATION @dialog_handle
    MESSAGE TYPE YourMessageType
    (@message_body)
GO


-- cost of creating a conversation for each message is expensive.
-- That's why you want to reuse conversations sending multiple messages
-- per conversation to reduce the overhead of sending messages
-- You can easily do this by logging the conversation handle to a table:

CREATE TABLE dbo.SSB_Settings
(
    [Source] sysname NOT NULL,
    [Destination] sysname NOT NULL,
    [Contract] sysname NOT NULL,
    [dialog_handle] uniqueidentifier
        CONSTRAINT PK_SSB_Setting PRIMARY KEY ([Source], [Destination], [Contract])
)

/**********************************************************************************************/
-- In a high-load environment, a stored procedure could be used to decide if a new conversation should
-- be created, as well as storing the value as needed
/**********************************************************************************************/
CREATE PROCEDURE dbo.CreateConversation
    @Destination sysname,
    @Source sysname,
    @Contract sysname,
    @MessageType sysname,
    @MessageBody XML,
    @dialog_handle uniqueidentifier
AS
/*Get the conversation id.*/
SELECT @dialog_handle = dialog_handle
FROM dbo.SSB_Settings
WHERE [Source] = @Source
  AND [Destination] = @Destination
  AND [Contract] = @Contract;

/*If there is no current handle, or the conversation has had 1000 messages
sent on it, create a new conversation.*/
    IF @dialog_handle IS NULL OR
       (SELECT send_sequence
        FROM sys.conversation_endpoints
        WHERE conversation_id = @dialog_handle) >= 1000
        BEGIN
            BEGIN TRANSACTION
                /*If there is a conversation dialog handle signal the destination
                code that the old conversation is dead.*/
                IF @dialog_handle IS NOT NULL
                    BEGIN
                        UPDATE dbo.SSB_Settings
                        SET dialog_handle = NULL
                        WHERE [Source] = @Source
                          AND [Destination] = @Destination
                          AND	[Contract] = @Contract;

                        SEND ON CONVERSATION @dialog_handle
                            MESSAGE TYPE EndOfConversation;
                    END

                /*Setup the new conversation*/
                BEGIN DIALOG CONVERSATION @dialog_handle
                    FROM SERVICE @Source
                    TO SERVICE @Destination
                    ON CONTRACT @Contract;

                /*Log the new conversation ID*/
                UPDATE dbo.SSB_Settings
                SET dialog_handle = @dialog_handle
                WHERE [Source] = @Source
                  AND [Destination] = @Destination
                  AND [Contract] = @Contract;

                IF @@ROWCOUNT = 0
                    INSERT INTO dbo.SSB_Settings
                    ([Source], [Destination], [Contract], [dialog_handle])
                    VALUES
                        (@Source, @Destination, @Contract, @dialog_handle);
        END;

/*Send the message*/
    SEND ON CONVERSATION @dialog_handle
        MESSAGE TYPE @MessageType
        (@MessageBody);

/*Verify that the conversation handle is still the one logged in the table.
  If not then mark this conversation as done.*/
    IF (SELECT dialog_handle
        FROM dbo.SSB_Settings
        WHERE [Source] = @Source
          AND [Destination] = @Destination
          AND [Contract] = @Contract) <> @dialog_handle
        SEND ON CONVERSATION @dialog_handle
            MESSAGE TYPE EndOfConversation;
GO

/**********************************************************************************************/
-- receiving messages

DECLARE @dialog_handle UNIQUEIDENTIFIER, @message_body XML

RECEIVE TOP 1 @dialog_handle = conversation_handle,
    @message_body = CAST(@message_body as XML)
    FROM YourDestinationQueue

/*Do whatever needs to be done with your XML document*/
END CONVERSATION @dialog_handle


-- Example:
-- The following code shows how to receive multiple messages in a single statement.
-- ************************************************************************************************
DECLARE @dialog_handle UNIQUEIDENTIFIER, @message_body XML

DECLARE @Messages TABLE
                  (
                      conversation_handle uniqueidentifier,
                      message_type sysname,
                      message_body VARBINARY(MAX)
                  )

WAITFOR
    (
    RECEIVE TOP (1000) conversation_handle, message_type_name, message_body
        FROM YourDestinationQueue
        INTO @Messages
    )

DECLARE cur CURSOR FOR
    select conversation_handle, CAST(message_body AS XML)
    FROM @Messages
    WHERE message_body IS NOT NULL

OPEN cur
FETCH NEXT FROM cur INTO @dialog_handle, @message_body
WHILE @@FETCH_STATUS = 0
    BEGIN
        /*Do whatever needs to be done with your XML document*/
        FETCH NEXT FROM cur INTO @dialog_handle, @message_body
    END
CLOSE cur
DEALLOCATE cur;

IF EXISTS (SELECT * FROM @Messages WHERE message_type = 'EndOfConversation')
    END CONVERSATION @dialog_handle
GO


/**********************************************************************************************/
/*  Sending Messages Between Instances
		1. First, configure the Database Master Key in the master database.
		2. Then, configure the Database Master Key in the application database.
		3. Next, create a certificate in each database.
		4. Exchange the certificates between the databases.
		5. Now create SQL Service Broker Endpoints on each instance.
		6. Finally, configure routes to connect to the remote instances SQL Service Broker Endpoint.
*/

-- Database Master Key
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'YourSecurePassword1!'
/*
	After you create the database master key, back it up using the BACKUP MASTER KEY statement so
	that the master key can be recovered if a database failure occurs. Securely store the backup of the
	database master key at an offsite location.
*/

-- Creating Certificates
CREATE CERTIFICATE MyServiceBrokerCertificate
    WITH SUBJECT = 'Service Broker Certificate',
    START_DATE = '1/1/2011',
    EXPIRY_DATE = '12/31/2099'

-- Exchanging Certificates
BACKUP CERTIFICATE MyServiceBrokerCertificate
    TO FILE='C:\MyServiceBrokerCertificate.cer'
CREATE CERTIFICATE MyServiceBrokerCertificate
    FROM FILE='c:\MyServiceBrokerCertificate.cer'

-- SQL Service Broker Endpoints
USE master
GO
CREATE ENDPOINT ServiceBrokerEndpoint
    STATE = STARTED
    AS TCP (LISTENER_PORT = 1234, LISTENER_IP=ALL)
    FOR SERVICE_BROKER
        (AUTHENTICATION = CERTIFICATE MyServiceBrokerCertificate,
        ENCRYPTION = REQUIRED ALGORITHM RC4);
GO

-- External activation service
/*
	http://www.microsoft.com/en-us/download/details.aspx?id=8824
*/
CREATE QUEUE dbo.MyDestinationQueueEA
GO
CREATE SERVICE MyDestinationServiceEA
    ON QUEUE dbo.MyDestinationQueueEA
    (
    [http://schemas.microsoft.com/SQL/Notifications/PostEventNotification]
    )
GO
CREATE EVENT NOTIFICATION MyDestinationNotificationEA
    ON QUEUE MyDestinationQueue
    FOR QUEUE_ACTIVATION
    TO SERVICE 'MyDestinationServiceEA', 'current database'
GO