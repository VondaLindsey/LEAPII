Common package for reuseable LEAP code. Contains:
-------------------------------------------------------------------------------------------------------
-- Procedure Name : SPLIT_TRANSFORM_BULK_ORDER
--
-- Description    : Perform the "Split/Transform" algorthim on a given bulk order-allocation.
--                  Create purchase orders for the actual, correct wh associated with a store.
--                  The "9401" bulk order process remains in place for the buyers and allocators.
--                  The new purchase orders are for the appropriate (actual) wh to receive on.
--                  This eliminates 9401 receiving which, resolves many issues including:
--                  Receiving on 9401 at the wh, then a different PO at the store,
--                  Writing incorrect transactions (over 5 million at this point)
--                  in the stock ledger for 9401 which, then need to be reversed out (the
--                  reversing process itself is also erroneous, requiring many "fixes").
--
-- Algorithm:       1) Select the input order from ordhead,
--                  2) Generate new order_no's based on the default wh (6-digit order_no||3-digit wh),
--                  3) Substitute 9401 for the real cross-dock wh (e.g. 9521,9531,9541),
--                  4) Create as many new orders as are default wh's for stores in the allocation(s),
--                  5) Select a "sample" (1 row) of ordsku, ordloc, alloc_head, alloc_detail,
--                  6) Generate ordsku records related to the new orders,
--                  7) Generate related ordloc recs, spliting order quantities by wh,
--                  8) Generate associated alloc_header records (using the base sequence),
--                  9) Generate alloc_detail records, splitting quantities by item-loc-wh.
--
-- Input Parameters 1) order_no
--
-- Output Parameters - None at this time (error processing is handled through exceptions).
--
-- *Note: No input order/allocation validation is performed here (that is up to the calling procedure).
--
----------------------------------------------------------------------------------------------
-- Procedure Name : SPLIT_TRANSFORM_BULK_ORDER
-- Description    : Perform the "Split/Transform" algorthim on a given bulk order.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Procedure Name : SPLIT_TRANSFORM_HOLD_BACK
-- Description    : Perform the "Split/Transform" algorthim on a hold back allocation.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Function Name : GET_CONSTANT_VALUE
-- Description   : Return a package constant from SQL 
-- e.g. select GET_CONSTANT_VALUE('SMR_LEAP_INTERFACE_SQL.SPLIT_PO_ORDER_LENGTH') from dual;
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Function Name : GET_ORDER_ITEM_HOLDBACK_QTY
-- Description    : Return the sum of the order-item holdback quantity. If zero retun null.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Procedure Name : PROCESS_APPROVED_ALLOC
-- Description    : Validate then call the "Split/Transform" algorthim for a given bulk order.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Function Name : SPLIT_ORDER_EXISTS
-- Description   : Check to see if Orders have previously been created.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Function Name : NOT_PACK_ITEM
-- Description   : Check to see if item is a vendor pack.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Function Name : APPR_HOLDBACK_ORDER_EXISTS
-- Description   : Check to see if Holdback (put away) orders have been created and approved.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Procedure Name : REMOVE_SPLIT_ORDERS
-- Description    : Remove "Split/Transform" created orders.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Procedure Name : UPDATE_SPLIT_ORDERS
-- Description    : If the bulk order is updated, update the split orders e.g. ordhead_rev
-- Note: this is just a 'stub' for now until revisions are implemented (during IF table write)
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Procedure Name : UPDATE_ORDER_CREATE_TIME
-- Description    : on order create success, update holdback staging table create datetime
----------------------------------------------------------------------------------------------

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

---------------------------------------------------------------------------------------------------
-- Function Name : WH_PO_EXTRACT
-- Purpose       : Function to extract WH PO's from SMR_RMS_WH_PO_DTL_STG
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Function Name : SDC_NEW_ITEM_LOC
-- Purpose       : call sdc_insert_item_loc
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Function Name : SDC_INSERT_ITEM_LOC
-- Purpose       : Insert new item loc
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Function Name : GENERATE_GROUP_ID
-- Purpose       : Function to generate Group Id for Interface tables
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Function Name : ADD_INT_QUEUE
-- Purpose       : Function to generate Group Id for Interface tables
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Function Name : RTV_EXTRACT
-- Purpose       : Function to Insert data into RTV interface tables
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------

-- Function Name : RTV_EXTRACT
-- Purpose       : Function to Insert data into RTV interface tables
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------

-- Function Name : PACK_DTL_EXTRACT
-- Purpose       : Function to Fetch Pack Details from RMS
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Function Name : CHECK_CASE_NAME
-- Description   : Check to see if item has a Cased in Box and can be handled in 9522 and 9532 warehouses.
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- Function Name : CHECK_PACK_SIZE
-- Description   : Check to see if Order contains Items with Pack Size > 1
----------------------------------------------------------------------------------------------
