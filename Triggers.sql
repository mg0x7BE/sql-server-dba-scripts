/**********************************************************************************************/
-- Create a trigger to audit changes to the product colors

CREATE TRIGGER TR_Product_Color_UPDATE
ON dbo.Product
FOR UPDATE
AS
BEGIN
  SET NOCOUNT ON;
  
  IF UPDATE(Color) BEGIN
    INSERT dbo.ProductColorAudit (ProductID, OldColor, NewColor)  
    SELECT i.ProductID, d.Color, i.Color
    FROM inserted AS i
    INNER JOIN deleted AS d
    ON i.ProductID = d.ProductID;
  END;
END;
GO

/**********************************************************************************************/
-- what triggers are installed?
SELECT type, name, parent_class_desc FROM sys.triggers
WHERE parent_class_desc = 'DATABASE'
UNION
SELECT type, name, parent_class_desc FROM sys.server_triggers
WHERE parent_class_desc = 'SERVER'

/**********************************************************************************************/