CREATE OR REPLACE PACKAGE SMR_WH_ADJ_SQL IS
-- Module Name: SMR_WH_ADJ_SQL
-- Description: This package will be used to create WA shipments to stores.
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== =========================================
-- 1.00    15-Feb-15  Murali              LEAP 2 Development
--------------------------------------------------------------------------------
PACKAGE_NAME CONSTANT VARCHAR2(30) := 'SMR_WH_ADJ_SQL';
pv_alloc_no alloc_header.alloc_no%TYPE;

------------------------------------------------------------------
-- FUNCTION: F_INIT_WH_SHIPMENTS
-- Purpose:  LOAD WH shipment into SMR_WH_ASN from Integration Tables
------------------------------------------------------------------
FUNCTION F_INIT_WH_ADJ(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

------------------------------------------------------------------
-- FUNCTION: F_PROCESS_RECEIPTS
-- Purpose:  Process valid WH shipments from SMR_WH_ASN
------------------------------------------------------------------
FUNCTION F_PROCESS_WH_ADJ(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

--------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_FILE
-- Purpose:  USED TO VALIDATE THE DATA IN THE Shipment Data AS LOADED INTO TABLE SMR_WH_ASN
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_ADJ(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

------------------------------------------------------------------
-- FUNCTION: F_FINISH_PROCESS
-- Purpose:  Finish processing WH shipments and update Integration Tables
------------------------------------------------------------------
FUNCTION F_FINISH_PROCESS(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

--------------------------------------------------------------------------------------------
-- Function : MAKE_ITEM_LOC
-- Purpose  : This function will create the entered item/location relationship in RMS
---------------------------------------------------------------------------------------------
FUNCTION F_MAKE_ITEM_LOC(O_error_message IN OUT VARCHAR2,
                       I_item          IN     VARCHAR2,
                       I_loc           IN     NUMBER,
                       I_loc_type      IN     VARCHAR2)
  RETURN BOOLEAN;

END SMR_WH_ADJ_SQL;
/