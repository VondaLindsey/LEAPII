CREATE OR REPLACE PACKAGE SMR_WH_RECEIVING IS
-- Module Name: SMR_WH_RECEIVING
-- Description: This package will be used to create shipments from the 944 SDC receipt file.
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== =========================================
-- 1.00    20-Feb-15 Murali      Leap 2   Wh recieving Process for PO and Stock Orders
--------------------------------------------------------------------------------
PACKAGE_NAME CONSTANT VARCHAR2(30) := 'SMR_WH_RECEIVING';
pv_alloc_no alloc_header.alloc_no%TYPE;

------------------------------------------------------------------
-- FUNCTION: F_INIT_WH_RECEIVING
-- Purpose:  LOAD WH Receipts into SMR_WH_RECEIVING_DATA from Integration Tables
------------------------------------------------------------------
FUNCTION F_INIT_WH_RECEIVING(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

------------------------------------------------------------------
-- FUNCTION: F_PROCESS_RECEIPTS
-- Purpose:  Process good receipts in
------------------------------------------------------------------
FUNCTION F_PROCESS_RECEIPTS(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;


--------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_CARTON
-- Purpose:  Function Used to Validate the carton . Invoked from the Form for correcting Receipt Errors
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_CARTON(O_error_message IN OUT VARCHAR2,
                           I_carton         IN OUT VARCHAR2,
                           O_valid         IN OUT BOOLEAN)
RETURN BOOLEAN;

--------------------------------------------------------------------------------------------
-- FUNCTION: F_PROCESS_CARTON
-- Purpose:  Process Reciepts from the Error table . Invoked from the Form
--------------------------------------------------------------------------------------------
FUNCTION F_PROCESS_CARTON(O_error_message IN OUT VARCHAR2,
                          I_carton_id     IN OUT VARCHAR2)

RETURN BOOLEAN;

--------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_FILE
-- Purpose:  USED TO VALIDATE THE DATA IN THE 944 FILE AS LOADED INTO TABLE smr_944_sqlload_data
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_RECEIPT(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

-- Function : MAKE_ITEM_LOC
-- Purpose  : This function will make the entered item/location relationship in RMS
---------------------------------------------------------------------------------------------
function F_MAKE_ITEM_LOC(O_error_message IN OUT VARCHAR2,
                         I_item          IN     VARCHAR2,
                         I_loc           IN     NUMBER,
                         I_loc_type      IN     VARCHAR2)
  RETURN BOOLEAN;


------------------------------------------------------------------
-- FUNCTION: F_FINISH_PROCESS
-- Purpose:  Finish processing WH Receipts and update Integration Tables
------------------------------------------------------------------
FUNCTION F_FINISH_PROCESS(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

END SMR_WH_RECEIVING;
/