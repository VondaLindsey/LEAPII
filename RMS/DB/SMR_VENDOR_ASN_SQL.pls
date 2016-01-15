CREATE OR REPLACE PACKAGE SMR_VENDOR_ASN_SQL IS
  -- Module Name: SMR_VENDOR_ASN_SQL
  -- Description: This package is used to validate the vendor 856 files
  --              AND load the data into the base shipment/shipsku tables.
  --
  -- Modification History
  -- Version Date      Developer   Issue    Description
  -- ======= ========= =========== ======== =========================================
  -- 1.00    20-Feb-15 Murali N    LEAP2    Initial version.
  --------------------------------------------------------------------------------
PACKAGE_NAME CONSTANT VARCHAR2(30) := 'SMR_VENDOR_ASN_SQL';

   -- Define a record to store asn records
   TYPE error_record IS RECORD(asn         smr_856_vendor_errors.asn%TYPE,
                               vendor      smr_856_vendor_errors.vendor%TYPE,
                               error_code  smr_856_vendor_errors.error_code%TYPE,
                               error_type  smr_856_vendor_errors.error_type%TYPE,
                               error_value smr_856_vendor_errors.error_value%TYPE,
                               file_type   smr_856_vendor_errors.file_type%TYPE);

   TYPE errorList IS TABLE OF error_record;
   P_errorList errorList;

   -- Define a record to store asn records
   TYPE asn_record IS RECORD(carton          shipsku.carton%TYPE,
                             asn             shipment.asn%TYPE,
                             destination     shipment.to_loc%TYPE,
                             ship_date       shipment.ship_date%TYPE,
                             est_arr_date    shipment.est_arr_date%TYPE,
                             carrier         shipment.courier%TYPE,
                             ship_pay_method ordhead.ship_pay_method%TYPE,
                             inbound_bol     shipment.ext_ref_no_in%TYPE,
                             supplier        ordhead.supplier%TYPE,
                             carton_ind      VARCHAR2(1));

   -- Define a record to store order records
   TYPE order_record IS RECORD(asn            shipment.asn%TYPE,
                               po_num         shipment.order_no%TYPE,
                               not_after_date ordhead.not_after_date%TYPE);

   -- Define a record to store carton records
   TYPE carton_record IS RECORD(asn        shipment.asn%TYPE,
                                po_num     shipment.order_no%TYPE,
                                carton_num carton.carton%TYPE,
                                location   carton.location%TYPE);

   -- Define a record to store item records
   TYPE item_record IS RECORD(asn         shipment.asn%TYPE,
                              po_num      shipment.order_no%TYPE,
                              carton_num  carton.carton%TYPE,
                              item        shipsku.item%TYPE,
                              ref_item    shipsku.ref_item%TYPE,
                              vpn         item_supplier.vpn%TYPE,
                              alloc_loc   carton.location%TYPE,
                              qty_shipped varchar2(20));

   -- Define a table based upon the carton record defined above.
   TYPE carton_table IS TABLE OF carton_record
      INDEX BY BINARY_INTEGER;

   -- Define a table based upon the item record defined above.
    TYPE item_table IS TABLE OF item_record
       INDEX BY BINARY_INTEGER;

   P_asn_record   asn_record   ;
   P_order_record order_record ;
   P_carton_table carton_table ;
   P_item_table   item_table   ;

   P_fail_date date;

------------------------------------------------------------------
-- FUNCTION: F_INIT_VEND_ASN
-- Purpose:  LOAD WH shipment into SMR_WH_ASN from Integration Tables
------------------------------------------------------------------
FUNCTION F_INIT_VEND_ASN(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

------------------------------------------------------------------
-- FUNCTION: F_LOAD_ASN_INT_TBL
-- Purpose:  Funtion to load ASN data into interface tables
------------------------------------------------------------------
FUNCTION F_LOAD_ASN_INT_TBL(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

------------------------------------------------------------------
-- FUNCTION: F_PROCESS_FILES
-- Purpose:  [Fill in purpose]
------------------------------------------------------------------
FUNCTION F_PROCESS_VEND_ASN(O_error_message IN OUT VARCHAR2)
RETURN BOOLEAN;

--------------------------------------------------------------------------------
-- Procedure Name: F_VALIDATE_WH_ASN
-- Purpose: [Fill in purpose]
--------------------------------------------------------------------------------
FUNCTION F_VALIDATE_VEND_ASN(O_error_message IN OUT VARCHAR2) 
 RETURN BOOLEAN;

------------------------------------------------------------------
-- FUNCTION: F_FINISH_PROCESS
-- Purpose:  Finish processing WH shipments and update Integration Tables
------------------------------------------------------------------
FUNCTION F_FINISH_PROCESS(O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN;

END SMR_VENDOR_ASN_SQL;
/