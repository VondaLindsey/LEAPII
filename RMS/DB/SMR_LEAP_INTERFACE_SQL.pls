CREATE OR REPLACE PACKAGE SMR_LEAP_INTERFACE_SQL AS
----------------------------------------------------------------------------------------------
-- Module:      SMR_LEAP_INTERFACE_SQL.pls
-- Description: This package houses functions and procedures to enable LEAP related
--              functionality (LEAP code interface).
--
-- Change History:
-- Version Date      Developer  Issue   Description
-- ======= ========= ========== ======= =======================================================
-- 1.00    02-DEC-14 Steve Fehr         Initial version.
--
-- ======= ========= ========== ======= =======================================================

SPLIT_PO_ORDER_LENGTH constant number := 9;

----------------------------------------------------------------------------------------------
-- Procedure Name : SPLIT_TRANSFORM_BULK_ORDER
-- Description    : Perform the "Split/Transform" algorthim on a given bulk order.
----------------------------------------------------------------------------------------------
PROCEDURE SPLIT_TRANSFORM_BULK_ORDER(I_order_no ordhead.order_no%TYPE);
/*
TYPE oh_rec is RECORD(header ORDHEAD%ROWTYPE);
TYPE oh_tbl_rec IS TABLE OF oh_rec INDEX BY BINARY_INTEGER;
*/

----------------------------------------------------------------------------------------------
-- Procedure Name : SPLIT_TRANSFORM_HOLD_BACK
-- Description    : Perform the "Split/Transform" algorthim on a hold back allocation.
----------------------------------------------------------------------------------------------
PROCEDURE SPLIT_TRANSFORM_HOLD_BACK(I_order_no ordhead.order_no%TYPE);

----------------------------------------------------------------------------------------------
-- Function Name : GET_CONSTANT_VALUE
-- Description   : Return a package constant from SQL 
-- e.g. select GET_CONSTANT_VALUE('SMR_LEAP_INTERFACE_SQL.SPLIT_PO_ORDER_LENGTH') from dual;
----------------------------------------------------------------------------------------------
FUNCTION GET_CONSTANT_VALUE(i_constant IN VARCHAR2) RETURN NUMBER DETERMINISTIC;

----------------------------------------------------------------------------------------------
-- Function Name : GET_ORDER_ITEM_HOLDBACK_QTY
-- Description    : Return the sum of the order-item holdback quantity. If zero retun null.
----------------------------------------------------------------------------------------------
FUNCTION GET_ORDER_ITEM_HOLDBACK_QTY(I_order_no ordhead.order_no%TYPE,
                                     I_item item_master.item%TYPE)
RETURN NUMBER;

----------------------------------------------------------------------------------------------
-- Procedure Name : PROCESS_APPROVED_ALLOC
-- Description    : Validate then call the "Split/Transform" algorthim for a given bulk order.
----------------------------------------------------------------------------------------------
PROCEDURE PROCESS_APPROVED_ALLOC(I_order_no ordhead.order_no%TYPE);

----------------------------------------------------------------------------------------------
-- Function Name : SPLIT_ORDER_EXISTS
-- Description   : Check to see if Orders have previously been created.
----------------------------------------------------------------------------------------------
FUNCTION SPLIT_ORDER_EXISTS(I_order_no ordhead.order_no%TYPE)
RETURN BOOLEAN;

----------------------------------------------------------------------------------------------
-- Function Name : NOT_PACK_ITEM
-- Description   : Check to see if item is a vendor pack.
----------------------------------------------------------------------------------------------
FUNCTION NOT_PACK_ITEM(I_item item_master.item%TYPE)
RETURN BOOLEAN;

----------------------------------------------------------------------------------------------
-- Function Name : APPR_HOLDBACK_ORDER_EXISTS
-- Description   : Check to see if Holdback (put away) orders have been created and approved.
----------------------------------------------------------------------------------------------
FUNCTION APPR_HOLDBACK_ORDER_EXISTS(I_order_no ordhead.order_no%TYPE)
RETURN BOOLEAN;

----------------------------------------------------------------------------------------------
-- Procedure Name : REMOVE_SPLIT_ORDERS
-- Description    : Remove "Split/Transform" created orders.
----------------------------------------------------------------------------------------------
PROCEDURE REMOVE_SPLIT_ORDERS( I_order_no ordhead.order_no%TYPE);

----------------------------------------------------------------------------------------------
-- Procedure Name : UPDATE_SPLIT_ORDERS
-- Description    : If the bulk order is updated, update the split orders e.g. ordhead_rev
-- Note: this is just a 'stub' for now until revisions are implemented (during IF table write)
----------------------------------------------------------------------------------------------
PROCEDURE UPDATE_SPLIT_ORDERS(I_order_no               ORDHEAD.ORDER_NO%TYPE);

----------------------------------------------------------------------------------------------
-- Procedure Name : UPDATE_ORDER_CREATE_TIME
-- Description    : on order create success, update holdback staging table create datetime
----------------------------------------------------------------------------------------------
PROCEDURE UPDATE_ORDER_CREATE_TIME(I_order_no ORDHEAD.ORDER_NO%TYPE );

---------------------------------------------------------------------------------------------------
-- Procedure Name : GET_CURR_INTENT_STATE
-- Purpose        : return the state of Allocation Intent for an order
-- Description: Determine current alloc intent state
--     4 cases: (will only be 1 record/order at a time)
--      1. Has been checked, not 'P'rocessed.
--      2. Has been checked, 'P'rocessed.
--      3. Has been unchecked, not 'P'rocessed.
--      4. Has been unchecked, 'P'rocessed.
---------------------------------------------------------------------------------------------------
PROCEDURE GET_CURR_INTENT_STATE(I_order_no          IN number,
                                O_alloc_intent_ind OUT varchar2,
                                O_status           OUT varchar2,
                                O_ARI_sent_ind     OUT varchar2,
                                O_ARI_sent_date    OUT date,
                                O_ship_recvd_ind   OUT varchar2,
                                O_qry_group_id OUT varchar2);

---------------------------------------------------------------------------------------------------
-- Function Name : WH_PO_EXTRACT
-- Purpose       : Function to extract WH PO's from SMR_RMS_WH_PO_DTL_STG
---------------------------------------------------------------------------------------------------
FUNCTION WH_PO_EXTRACT (O_error_message IN OUT VARCHAR2) return BOOLEAN;

---------------------------------------------------------------------------------------------------
-- Function Name : SDC_NEW_ITEM_LOC
-- Purpose       : call sdc_insert_item_loc
---------------------------------------------------------------------------------------------------
PROCEDURE SDC_NEW_ITEM_LOC( O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                            I_item          IN     ITEM_LOC.ITEM%TYPE,
                            I_wh            IN     ITEM_LOC.LOC%TYPE );

---------------------------------------------------------------------------------------------------
-- Function Name : SDC_INSERT_ITEM_LOC
-- Purpose       : Insert new item loc
---------------------------------------------------------------------------------------------------
PROCEDURE SDC_INSERT_ITEM_LOC( O_error_message   IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                               I_item            IN     ITEM_LOC.ITEM%TYPE,
                               I_location        IN     ITEM_LOC.LOC%TYPE,
                               I_loc_type        IN     ITEM_LOC.LOC_TYPE%TYPE);


---------------------------------------------------------------------------------------------------
-- Function Name : GENERATE_GROUP_ID
-- Purpose       : Function to generate Group Id for Interface tables
---------------------------------------------------------------------------------------------------
FUNCTION GENERATE_GROUP_ID (O_error_message IN OUT VARCHAR2,
                           I_INTERFACE_ID IN SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE,
                           O_GROUP_ID IN OUT SMR_RMS_INT_QUEUE.GROUP_ID%TYPE)
RETURN BOOLEAN;

---------------------------------------------------------------------------------------------------
-- Function Name : ADD_INT_QUEUE
-- Purpose       : Function to generate Group Id for Interface tables
---------------------------------------------------------------------------------------------------
FUNCTION ADD_INT_QUEUE (O_error_message IN OUT VARCHAR2,
                        I_INTERFACE_ID IN SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE,
                        I_GROUP_ID IN SMR_RMS_INT_QUEUE.GROUP_ID%TYPE)
RETURN BOOLEAN;

---------------------------------------------------------------------------------------------------
-- Function Name : RTV_EXTRACT
-- Purpose       : Function to Insert data into RTV interface tables
---------------------------------------------------------------------------------------------------
FUNCTION RTV_EXTRACT (O_error_message IN OUT VARCHAR2)
RETURN BOOLEAN;
---------------------------------------------------------------------------------------------------

-- Function Name : RTV_EXTRACT
-- Purpose       : Function to Insert data into RTV interface tables
---------------------------------------------------------------------------------------------------
FUNCTION RTW_EXTRACT (O_error_message IN OUT VARCHAR2)
RETURN BOOLEAN;
---------------------------------------------------------------------------------------------------

-- Function Name : PACK_DTL_EXTRACT
-- Purpose       : Function to Fetch Pack Details from RMS
---------------------------------------------------------------------------------------------------
FUNCTION PACK_DTL_EXTRACT (O_error_message IN OUT VARCHAR2)
RETURN BOOLEAN;
---------------------------------------------------------------------------------------------------
-- Function Name : CHECK_CASE_NAME
-- Description   : Check to see if item has a Cased in Box and can be handled in 9522 and 9532 warehouses.
----------------------------------------------------------------------------------------------
FUNCTION CHECK_CASE_NAME(O_error_message IN OUT VARCHAR2,
                         I_Exists   OUT VARCHAR2,
                         I_order_no IN ORDHEAD.ORDER_NO%type,  
                         I_item IN item_master.item%TYPE)
RETURN BOOLEAN;
----------------------------------------------------------------------------------------------
-- Function Name : CHECK_PACK_SIZE
-- Description   : Check to see if Order contains Items with Pack Size > 1
----------------------------------------------------------------------------------------------
FUNCTION CHECK_PACK_SIZE (O_error_message IN OUT VARCHAR2,
                         I_Exists   OUT VARCHAR2,
                         I_order_no IN ORDHEAD.ORDER_NO%type)
RETURN BOOLEAN;
----------------------------------------------------------------------------------------------



END SMR_LEAP_INTERFACE_SQL;
/