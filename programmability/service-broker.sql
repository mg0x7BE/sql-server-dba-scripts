/*
    Programmability / Service Broker
    Service Broker object model and messaging templates.
*/

-- Service Broker is in maintenance mode: no new features since 2012, kept for compatibility only.

-- List databases with Service Broker enabled.
-- First check when a queue or activation procedure is not firing.
SELECT
    d.name,
    d.is_broker_enabled,
    d.service_broker_guid,
    d.is_honor_broker_priority_on
FROM sys.databases AS d
WHERE d.is_broker_enabled = 1
ORDER BY d.name;
GO

-- Enable Service Broker on a database.
-- ROLLBACK IMMEDIATE forces out existing sessions; run during a maintenance window.
USE [master];
GO
ALTER DATABASE [YourDatabase] SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;
GO

-- Catalog views: message types, contracts, queues, services.
-- Quick inventory of the broker objects in the current database.
USE [YourDatabase];
GO
SELECT * FROM sys.service_message_types;
SELECT * FROM sys.service_contracts;
SELECT * FROM sys.service_contract_message_usages;
SELECT * FROM sys.service_queues;
GO

-- Contract details: which message types each contract carries and who may send them.
-- Use when verifying a contract definition before sending.
SELECT
    c.name AS contract_name,
    mt.name AS message_type,
    cmu.is_sent_by_initiator,
    cmu.is_sent_by_target,
    mt.validation_desc
FROM sys.service_contract_message_usages AS cmu
JOIN sys.service_message_types AS mt
    ON mt.message_type_id = cmu.message_type_id
JOIN sys.service_contracts AS c
    ON c.service_contract_id = cmu.service_contract_id
ORDER BY c.name, mt.name;
GO

-- Services and their associated contracts.
-- Maps each service to the contracts it is allowed to use.
SELECT
    s.name AS service_name,
    c.name AS contract_name
FROM sys.services AS s
JOIN sys.service_contract_usages AS cu
    ON cu.service_id = s.service_id
JOIN sys.service_contracts AS c
    ON c.service_contract_id = cu.service_contract_id
ORDER BY s.name, c.name;
GO

-- Inspect open conversations and their state.
-- Use to find stuck or one-sided dialogs (state_desc, lifetime, retries).
SELECT
    ce.conversation_handle,
    ce.conversation_id,
    ce.state_desc,
    ce.far_service,
    ce.is_initiator,
    ce.send_sequence,
    ce.receive_sequence
FROM sys.conversation_endpoints AS ce
ORDER BY ce.state_desc, ce.conversation_id;
GO

-- Message Types
-- A message type validates that a message body is in the expected format.
-- Validation: NONE, EMPTY, WELL_FORMED_XML, VALID_XML WITH SCHEMA COLLECTION.
CREATE MESSAGE TYPE YourMessageType
    AUTHORIZATION dbo
    VALIDATION = WELL_FORMED_XML;
GO

-- Contracts
-- A contract defines which message types a single conversation may use,
-- and who may send each: INITIATOR, TARGET, or ANY.
CREATE CONTRACT MyContract
    AUTHORIZATION dbo
    (YourMessageType SENT BY ANY);
GO

CREATE CONTRACT MyTwoWayContract
    AUTHORIZATION dbo
    (YourMessageType SENT BY INITIATOR,
     AnotherMessageType SENT BY TARGET);
GO

-- Queues
-- A queue physically stores messages between send and receive.
-- ACTIVATION is often added later via ALTER QUEUE once the procedure exists.
CREATE QUEUE YourQueue_Source
    WITH STATUS = ON,                -- messages can be received from the queue
    RETENTION = OFF,                 -- ON keeps received messages for auditing
    ACTIVATION (
        STATUS = OFF,                -- enable/disable the activation procedure
        PROCEDURE_NAME = dbo.MySourceActivationProcedure,
        MAX_QUEUE_READERS = 1,       -- threads, each calling the activated proc
        EXECUTE AS OWNER),           -- SELF, OWNER, or a valid user
    POISON_MESSAGE_HANDLING (STATUS = ON);  -- disable queue after 5 consecutive rollbacks
GO

-- Two queues are typical: one source queue and one destination queue.

-- Services
-- A service binds a queue to the set of contracts allowed when messaging it.
CREATE SERVICE YourService_Source
    AUTHORIZATION dbo
    ON QUEUE dbo.YourQueue_Source
    (MyContract);
GO

-- Routes
-- A route controls which database/instance messages are delivered to.
-- BROKER_INSTANCE is the target db's service_broker_guid from sys.databases.
-- ADDRESS: TCP host:port, 'LOCAL' (same instance), or 'TRANSPORT'.
CREATE ROUTE ExpenseRoute
    WITH SERVICE_NAME = 'MyService',          -- case-sensitive; optional
    BROKER_INSTANCE = '<target-broker-guid>',
    ADDRESS = 'TCP://<target-host>:<port>';
GO

-- Broker Priorities
-- Assigns a priority (1-10) so higher conversations are processed first.
-- Requires the database HONOR_BROKER_PRIORITY setting to be ON.
CREATE BROKER PRIORITY HighPriority
    FOR CONVERSATION
    SET (
        CONTRACT_NAME = MyContract,
        LOCAL_SERVICE_NAME = ANY,
        REMOTE_SERVICE_NAME = N'ANY',
        PRIORITY_LEVEL = 8);
GO

-- Get the conversation group of the next message to process.
-- Used to keep related messages processed together.
DECLARE @conversation_group_id UNIQUEIDENTIFIER;
GET CONVERSATION GROUP @conversation_group_id
    FROM YourQueue_Source;
GO

-- Send a message: open a dialog, then SEND on it.
-- Simplest send pattern; one conversation per message is expensive (see below).
DECLARE @message_body XML, @dialog_handle UNIQUEIDENTIFIER;

SET @message_body = (
    SELECT * FROM sys.all_objects AS o FOR XML AUTO, ROOT('root'));

BEGIN DIALOG CONVERSATION @dialog_handle
    FROM SERVICE [YourSourceService]
    TO SERVICE 'YourDestinationService'
    ON CONTRACT [MyContract]
    WITH ENCRYPTION = OFF;

SEND ON CONVERSATION @dialog_handle
    MESSAGE TYPE YourMessageType (@message_body);
GO

-- Receive a single message and end the conversation.
-- Basic consumer pattern for a destination queue.
DECLARE @dialog_handle UNIQUEIDENTIFIER, @message_body XML;

RECEIVE TOP (1)
    @dialog_handle = conversation_handle,
    @message_body = CAST(message_body AS XML)
FROM YourDestinationQueue;

-- process @message_body here
END CONVERSATION @dialog_handle;
GO

-- Receive many messages in one statement, WAITFOR until some arrive.
-- Higher-throughput consumer; iterate the batch, then END CONVERSATION on the
-- system EndDialog message type.
DECLARE @dialog_handle UNIQUEIDENTIFIER, @message_type sysname, @message_body XML;

DECLARE @Messages TABLE (
    conversation_handle UNIQUEIDENTIFIER,
    message_type sysname,
    message_body VARBINARY(MAX));

WAITFOR (
    RECEIVE TOP (1000)
        conversation_handle,
        message_type_name,
        message_body
    FROM YourDestinationQueue
    INTO @Messages);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT conversation_handle, message_type, CAST(message_body AS XML)
    FROM @Messages;

OPEN cur;
FETCH NEXT FROM cur INTO @dialog_handle, @message_type, @message_body;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- process @message_body here when message_type is an application type

    -- system EndDialog: peer closed its side, so close ours
    IF @message_type = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
        END CONVERSATION @dialog_handle;

    FETCH NEXT FROM cur INTO @dialog_handle, @message_type, @message_body;
END
CLOSE cur;
DEALLOCATE cur;
GO

-- Reuse a conversation across messages to avoid per-message dialog overhead.
-- Log the dialog handle in a table and reuse it until it ages out.
CREATE TABLE dbo.SSB_Settings (
    [Source] sysname NOT NULL,
    [Destination] sysname NOT NULL,
    [Contract] sysname NOT NULL,
    dialog_handle UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_SSB_Settings PRIMARY KEY ([Source], [Destination], [Contract]));
GO

-- Procedure that reuses a logged conversation, recycling it after 1000 messages.
-- Use in high-load senders to minimize conversation creation cost.
CREATE PROCEDURE dbo.CreateConversation
    @Destination sysname,
    @Source sysname,
    @Contract sysname,
    @MessageType sysname,
    @MessageBody XML
AS
BEGIN
    DECLARE @dialog_handle UNIQUEIDENTIFIER;

    -- get the current handle for this source/destination/contract
    SELECT @dialog_handle = dialog_handle
    FROM dbo.SSB_Settings
    WHERE [Source] = @Source
      AND [Destination] = @Destination
      AND [Contract] = @Contract;

    -- no handle yet, or it has carried >= 1000 messages: start a new one
    IF @dialog_handle IS NULL
       OR (SELECT send_sequence
           FROM sys.conversation_endpoints
           WHERE conversation_handle = @dialog_handle) >= 1000
    BEGIN
        BEGIN TRANSACTION;

            -- close the old conversation and clear it
            IF @dialog_handle IS NOT NULL
            BEGIN
                UPDATE dbo.SSB_Settings
                SET dialog_handle = NULL
                WHERE [Source] = @Source
                  AND [Destination] = @Destination
                  AND [Contract] = @Contract;

                END CONVERSATION @dialog_handle;
            END

            BEGIN DIALOG CONVERSATION @dialog_handle
                FROM SERVICE @Source
                TO SERVICE @Destination
                ON CONTRACT @Contract
                WITH ENCRYPTION = OFF;

            UPDATE dbo.SSB_Settings
            SET dialog_handle = @dialog_handle
            WHERE [Source] = @Source
              AND [Destination] = @Destination
              AND [Contract] = @Contract;

            IF @@ROWCOUNT = 0
                INSERT INTO dbo.SSB_Settings
                    ([Source], [Destination], [Contract], dialog_handle)
                VALUES (@Source, @Destination, @Contract, @dialog_handle);

        COMMIT TRANSACTION;
    END

    SEND ON CONVERSATION @dialog_handle
        MESSAGE TYPE @MessageType (@MessageBody);

    -- if the logged handle changed underneath us, close this one
    IF (SELECT dialog_handle
        FROM dbo.SSB_Settings
        WHERE [Source] = @Source
          AND [Destination] = @Destination
          AND [Contract] = @Contract) <> @dialog_handle
        END CONVERSATION @dialog_handle;
END
GO

-- Cross-instance messaging: certificate-secured Service Broker endpoints.
-- Steps: master key per instance, certificate per database, exchange certs,
-- create endpoints, then routes pointing at the remote endpoints.

-- Database master key. Back it up with BACKUP MASTER KEY and store offsite.
-- Replace the placeholder with a strong password from your secret store.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong-password-placeholder>';
GO

-- Certificate used to authenticate the endpoint.
-- Set START_DATE/EXPIRY_DATE to your own validity window.
CREATE CERTIFICATE MyServiceBrokerCertificate
    WITH SUBJECT = 'Service Broker Certificate',
    START_DATE = '<yyyy-mm-dd>',
    EXPIRY_DATE = '<yyyy-mm-dd>';
GO

-- Exchange certificates: back up the public key, copy to the remote instance,
-- then create the certificate there FROM FILE. Use a secured path/share.
BACKUP CERTIFICATE MyServiceBrokerCertificate
    TO FILE = '<path>\MyServiceBrokerCertificate.cer';
GO
-- run on the remote instance against the copied file:
-- CREATE CERTIFICATE MyServiceBrokerCertificate
--     FROM FILE = '<path>\MyServiceBrokerCertificate.cer';
-- GO

-- Service Broker endpoint. Use AES; RC4 is broken and removed.
USE [master];
GO
CREATE ENDPOINT ServiceBrokerEndpoint
    STATE = STARTED
    AS TCP (LISTENER_PORT = 4022, LISTENER_IP = ALL)
    FOR SERVICE_BROKER (
        AUTHENTICATION = CERTIFICATE MyServiceBrokerCertificate,
        ENCRYPTION = REQUIRED ALGORITHM AES);
GO

-- External Activation: notify a service when a queue activates.
-- Used by the external activator to launch an out-of-process consumer.
USE [YourDatabase];
GO
CREATE QUEUE dbo.MyDestinationQueueEA;
GO
CREATE SERVICE MyDestinationServiceEA
    ON QUEUE dbo.MyDestinationQueueEA
    ([http://schemas.microsoft.com/SQL/Notifications/PostEventNotification]);
GO
CREATE EVENT NOTIFICATION MyDestinationNotificationEA
    ON QUEUE dbo.MyDestinationQueueEA
    FOR QUEUE_ACTIVATION
    TO SERVICE 'MyDestinationServiceEA', 'current database';
GO
