CREATE OR REPLACE PACKAGE SMR_LEAP_ASN_SQL AS
/*=====================================================================================*/
--
-- Module Name: SMR_LEAP_ASN_SQL
-- Description: Custom version of Copy of SMR_ASN_SQL created for Leap Changes
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== ===============================================
-- 1.00    10-Mar-15 Murali N    LEAP     Copy of SMR_ASN_SQL created for Leap Changes
-----------------------------------------------------------------------------------------
/*=====================================================================================*/

--used by the ASN subscribe packages and their dependent packages
TYPE shipment_shipsku_TBL is table of shipsku.shipment%TYPE INDEX BY BINARY_INTEGER;
TYPE shipment_seq_no_TBL is table of shipsku.seq_no%TYPE INDEX BY BINARY_INTEGER;
TYPE item_shipsku_TBL is table of shipsku.item%TYPE INDEX BY BINARY_INTEGER;
TYPE distro_no_shipsku_TBL is table of shipsku.distro_no%TYPE INDEX BY BINARY_INTEGER;
TYPE ref_item_shipsku_TBL is table of shipsku.ref_item%TYPE INDEX BY BINARY_INTEGER;
TYPE carton_shipsku_TBL is table of shipsku.carton%TYPE INDEX BY BINARY_INTEGER;
TYPE inv_status_shipsku_TBL is table of shipsku.inv_status%TYPE INDEX BY BINARY_INTEGER;
TYPE status_code_shipsku_TBL is table of shipsku.status_code%TYPE INDEX BY BINARY_INTEGER;
TYPE qty_received_shipsku_TBL is table of shipsku.qty_received%TYPE INDEX BY BINARY_INTEGER;
TYPE unit_cost_shipsku_TBL is table of shipsku.unit_cost%TYPE INDEX BY BINARY_INTEGER;
TYPE unit_retail_shipsku_TBL is table of shipsku.unit_retail%TYPE INDEX BY BINARY_INTEGER;
TYPE qty_expected_shipsku_TBL is table of shipsku.qty_expected%TYPE INDEX BY BINARY_INTEGER;
TYPE ind_TBL is table of VARCHAR2(1) INDEX BY BINARY_INTEGER;

P_shipments shipment_shipsku_TBL;
P_seq_nos shipment_seq_no_TBL;
P_items item_shipsku_TBL;
P_distro_nos distro_no_shipsku_TBL;
P_ref_items ref_item_shipsku_TBL;
P_cartons carton_shipsku_TBL;
P_inv_statuses inv_status_shipsku_TBL;
P_status_codes status_code_shipsku_TBL;
P_qty_receiveds qty_received_shipsku_TBL;
P_unit_costs unit_cost_shipsku_TBL;
P_unit_retails unit_retail_shipsku_TBL;
P_qty_expecteds qty_expected_shipsku_TBL;

P_shipskus_size NUMBER := 0;

-----------------------------------------------------------------------------------
FUNCTION VALIDATE_LOCATION(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                           O_loc_type         IN OUT SHIPMENT.TO_LOC_TYPE%TYPE,
                           I_location         IN     SHIPMENT.TO_LOC%TYPE)
return BOOLEAN;
-----------------------------------------------------------------------------------
FUNCTION PROCESS_ORDER(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                       O_order_no         IN OUT ORDHEAD.ORDER_NO%TYPE,
                       O_pre_mark_ind     IN OUT ORDHEAD.PRE_MARK_IND%TYPE,
                       O_shipment         IN OUT SHIPMENT.SHIPMENT%TYPE,
                       O_ship_match       IN OUT BOOLEAN,
                       I_asn              IN     SHIPMENT.ASN%TYPE,
                       I_order_no         IN     SHIPMENT.ORDER_NO%TYPE,
                       I_to_loc           IN     SHIPMENT.TO_LOC%TYPE,
                       I_to_loc_type      IN     SHIPMENT.TO_LOC_TYPE%TYPE,
                       I_ship_pay_method  IN     ORDHEAD.SHIP_PAY_METHOD%TYPE,
                       I_not_after_date   IN     ORDHEAD.NOT_AFTER_DATE%TYPE,
                       I_ship_date        IN     SHIPMENT.SHIP_DATE%TYPE,
                       I_est_arr_date     IN     SHIPMENT.EST_ARR_DATE%TYPE,
                       I_courier          IN     SHIPMENT.COURIER%TYPE,
                       I_inbound_bol      IN     SHIPMENT.EXT_REF_NO_IN%TYPE,
                       I_supplier         IN     ORDHEAD.SUPPLIER%TYPE,
                       I_carton_ind       IN     VARCHAR2,
                       I_message_type     IN     VARCHAR2,
                       I_order_loc        IN     NUMBER,
                       I_carton           IN     carton.carton%type)

return BOOLEAN;
-----------------------------------------------------------------------------------
FUNCTION VALIDATE_CARTON(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                         I_carton           IN     CARTON.CARTON%TYPE,
                         I_alloc_loc        IN     CARTON.LOCATION%TYPE)
return BOOLEAN;
----------------------------------------------------------------------------------
FUNCTION CHECK_ITEM(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                    I_shipment         IN     SHIPMENT.SHIPMENT%TYPE,
                    I_supplier         IN     ORDHEAD.SUPPLIER%TYPE,
                    I_asn              IN     SHIPMENT.ASN%TYPE,
                    I_order_no         IN     SHIPMENT.ORDER_NO%TYPE,
                    I_location         IN     SHIPMENT.TO_LOC%TYPE,
                    I_alloc_loc        IN     CARTON.LOCATION%TYPE,
                    I_item             IN     SHIPSKU.ITEM%TYPE,
                    I_ref_item         IN     SHIPSKU.REF_ITEM%TYPE,
                    I_vpn              IN     ITEM_SUPPLIER.VPN%TYPE,
                    I_carton           IN     SHIPSKU.CARTON%TYPE,
                    I_premark_ind      IN     ORDHEAD.PRE_MARK_IND%TYPE,
                    I_qty              IN     SHIPSKU.QTY_EXPECTED%TYPE,
                    I_ship_match       IN     BOOLEAN,
                    I_loc_type         IN     ITEM_LOC.LOC_TYPE%TYPE)
return BOOLEAN;
-----------------------------------------------------------------------------------
FUNCTION CREATE_INVOICE(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                        I_shipment         IN     SHIPMENT.SHIPMENT%TYPE,
                        I_supplier         IN     ORDHEAD.SUPPLIER%TYPE,
                        I_ship_match       IN     BOOLEAN)
return BOOLEAN;
-----------------------------------------------------------------------------------
FUNCTION DELETE_ASN(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                    I_asn              IN     SHIPMENT.ASN%TYPE)
return BOOLEAN;
-----------------------------------------------------------------------------------
FUNCTION DO_SHIPSKU_INSERTS(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE)
return BOOLEAN;
--------------------------------------------------------------------------------------------
FUNCTION RESET_GLOBALS(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE)
return BOOLEAN;
--------------------------------------------------------------------------------------------
FUNCTION PROCESS_ORDER_ONLINE(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                              O_order_no         IN OUT ORDHEAD.ORDER_NO%TYPE,
                              O_pre_mark_ind     IN OUT ORDHEAD.PRE_MARK_IND%TYPE,
                              O_shipment         IN OUT SHIPMENT.SHIPMENT%TYPE,
                              I_asn              IN     SHIPMENT.ASN%TYPE,
                              I_order_no         IN     SHIPMENT.ORDER_NO%TYPE,
                              I_to_loc           IN     SHIPMENT.TO_LOC%TYPE,
                              I_to_loc_type      IN     SHIPMENT.TO_LOC_TYPE%TYPE,
                              I_ship_pay_method  IN     ORDHEAD.SHIP_PAY_METHOD%TYPE,
                              I_not_after_date   IN     ORDHEAD.NOT_AFTER_DATE%TYPE,
                              I_ship_date        IN     SHIPMENT.SHIP_DATE%TYPE,
                              I_est_arr_date     IN     SHIPMENT.EST_ARR_DATE%TYPE,
                              I_courier          IN     SHIPMENT.COURIER%TYPE,
                              I_no_boxes         IN     SHIPMENT.NO_BOXES%TYPE,
                              I_comments         IN     SHIPMENT.COMMENTS%TYPE,
                              I_inbound_bol      IN     SHIPMENT.EXT_REF_NO_IN%TYPE,
                              I_supplier         IN     ORDHEAD.SUPPLIER%TYPE,
                              I_carton_ind       IN     VARCHAR2)
return BOOLEAN;
--------------------------------------------------------------------------------------------
FUNCTION NEW_SHIPMENT_ONLINE(O_error_message      IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                             O_shipment           IN OUT SHIPMENT.SHIPMENT%TYPE,
                             I_asn                IN     SHIPMENT.ASN%TYPE,
                             I_order_no           IN     SHIPMENT.ORDER_NO%TYPE,
                             I_location           IN     SHIPMENT.TO_LOC%TYPE,
                             I_loc_type           IN     SHIPMENT.TO_LOC_TYPE%TYPE,
                             I_shipdate           IN     SHIPMENT.SHIP_DATE%TYPE,
                             I_est_arr_date       IN     SHIPMENT.EST_ARR_DATE%TYPE,
                             I_carton_ind         IN     VARCHAR2,
                             I_inbound_bol        IN     SHIPMENT.EXT_REF_NO_IN%TYPE,
                             I_courier            IN     SHIPMENT.COURIER%TYPE,
                             I_no_boxes           IN     SHIPMENT.NO_BOXES%TYPE,
                             I_comments           IN     SHIPMENT.COMMENTS%TYPE,
                             I_bill_to_loc        IN     SHIPMENT.BILL_TO_LOC%TYPE,
                             I_bill_to_loc_type   IN     SHIPMENT.BILL_TO_LOC_TYPE%TYPE)
return BOOLEAN;
--------------------------------------------------------------------------------------------
END SMR_LEAP_ASN_SQL;
/