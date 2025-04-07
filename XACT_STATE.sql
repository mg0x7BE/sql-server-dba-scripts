/**********************************************************************************************/
/*
	To avoid rolling back an active transaction, 
	use the XACT_STATE function. XACT_STATE returns the following values:

	1	- The current request has an active, committable user transaction.
	0	- No active transaction.
	-1	- The current request has an active user transaction, but an error has occurred that has caused the transaction to be classified as an uncommittable transaction.
*/

BEGIN TRY
	BEGIN TRANSACTION;
		INSERT INTO dbo.SimpleOrders(custid, empid, orderdate) 
		VALUES (68,9,'2006-07-12');
		INSERT INTO dbo.SimpleOrderDetails(orderid,productid,unitprice,qty) 
		VALUES (1, 2,15.20,20);
	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	SELECT ERROR_NUMBER() AS ErrNum, ERROR_MESSAGE() AS ErrMsg;
	IF (XACT_STATE()) <> 0
		BEGIN
		ROLLBACK TRANSACTION;
		END;
	ELSE .... -- provide for other outcomes of XACT_STATE()
END CATCH;




