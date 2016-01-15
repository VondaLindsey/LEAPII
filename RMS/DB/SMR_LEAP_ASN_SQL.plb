CREATE OR REPLACE PACKAGE BODY SMR_LEAP_ASN_SQL AS
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

PROGRAM_ERROR    EXCEPTION;
----------------------------------------------------------------------------------------
-- Called by VALIDATE_CARTON
----------------------------------------------------------------------------------------
FUNCTION VALIDATE_LOCATION(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                           O_loc_type         IN OUT SHIPMENT.TO_LOC_TYPE%TYPE,
                           I_location         IN     SHIPMENT.TO_LOC%TYPE)
return BOOLEAN IS

   cursor C_LOC is
   select 'S'
     from store
    where store = I_location
    union all
   select 'W'
     from wh
    where wh = I_location;

BEGIN
   open C_LOC;
   fetch C_LOC into O_loc_type;
   close C_LOC;

   if O_loc_type is NULL then
      raise PROGRAM_ERROR;
   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('INV_LOC',
                                            I_location,
                                            NULL,
                                            NULL);
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.VALIDATE_LOCATION',
                                            to_char(SQLCODE));
      return FALSE;

END VALIDATE_LOCATION;

--------------------------------------------------------------------------

-----------------------------------------------------------------------------------
-- Called by PROCESS_ORDER
-----------------------------------------------------------------------------------
FUNCTION VALIDATE_ORDER(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                        O_order_no         IN OUT ORDHEAD.ORDER_NO%TYPE,
                        O_pre_mark_ind     IN OUT ORDHEAD.PRE_MARK_IND%TYPE,
                        O_import_id        IN OUT ORDHEAD.IMPORT_ID%TYPE,
                        O_import_type      IN OUT ORDHEAD.IMPORT_TYPE%TYPE,
                        I_order_no         IN     ORDHEAD.VENDOR_ORDER_NO%TYPE,
                        I_payment_method   IN     ORDHEAD.SHIP_PAY_METHOD%TYPE,
                        I_not_after_date   IN     ORDHEAD.NOT_AFTER_DATE%TYPE,
                        I_supplier         IN     ORDHEAD.SUPPLIER%TYPE)
return BOOLEAN IS

   L_status            ORDHEAD.STATUS%TYPE;
   L_payment_method    ORDHEAD.SHIP_PAY_METHOD%TYPE;
   L_order_currency    ORDHEAD.CURRENCY_CODE%TYPE;
   L_not_after_date    ORDHEAD.NOT_AFTER_DATE%TYPE;
   L_count             NUMBER;


   cursor C_ORD is
      select order_no,
             status,
             ship_pay_method,
             currency_code,
             not_after_date,
             pre_mark_ind,
             import_id,
             import_type
        from ordhead
       where order_no = TO_NUMBER(I_order_no)
         and supplier = NVL(I_supplier, supplier);

   cursor C_VEN_ORD is
      select order_no,
             status,
             ship_pay_method,
             currency_code,
             not_after_date,
             pre_mark_ind,
             import_id,
             import_type
        from ordhead
       where vendor_order_no = I_order_no
         and supplier = NVL(I_supplier, supplier);

BEGIN

   open C_ORD;
   fetch C_ORD into O_order_no,
                    L_status,
                    L_payment_method,
                    L_order_currency,
                    L_not_after_date,
                    O_pre_mark_ind,
                    O_import_id,
                    O_import_type;

   if C_ORD%NOTFOUND then
   -- check for an order using a vendor PO instead of a retek PO
      L_count := 0;
      -- need to find how many records have this vendor order number. If none,
      -- the order is not in the system. If more than one, we have a problem
      for rec in C_VEN_ORD LOOP
         O_order_no := rec.order_no;
         L_status := rec.status;
         L_payment_method := rec.ship_pay_method;
         L_order_currency := rec.currency_code;
         L_not_after_date := rec.not_after_date;
         O_pre_mark_ind   := rec.pre_mark_ind;
         O_import_id      := rec.import_id;
         O_import_type    := rec.import_type;
         L_count := L_count + 1;
      end LOOP;

      if L_count = 0 then
         O_error_message := SQL_LIB.GET_MESSAGE_TEXT('INV_ORDER_NO',
                                               NULL,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

      if L_count > 1 then
         O_error_message := SQL_LIB.GET_MESSAGE_TEXT('INV_ORDER_NO',
                                               NULL,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;
   end if;

   if NVL(L_payment_method, '-999') != NVL(I_payment_method, '-999') then
      -- pay method in file must be the same as what's on ordhead
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('INV_PAYMETHOD',
                                            NULL,
                                            NULL,
                                            NULL);
      raise PROGRAM_ERROR;
   end if;

   --For this custom interface we will accept shipments for orders not in A/C status
   /* OLR v1.00 BEGIN DELETE
   if L_status not in ('A', 'C') then
      -- must be in A or C status
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('INV_ORD_STATUS',
                                            NULL,
                                            NULL,
                                            NULL);
      raise PROGRAM_ERROR;
   end if;
   OLR v1.00 END DELETE */

   if to_date(I_not_after_date, 'DD-MON-YYYY') > L_not_after_date then
      --file not after date can't be after retek order_no nad
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('INV_NAD_DATE',
                                            I_order_no,
                                            NULL,
                                            NULL);
      raise PROGRAM_ERROR;
   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.VALIDATE_ORDER',
                                            to_char(SQLCODE));
      return FALSE;
END VALIDATE_ORDER;
-----------------------------------------------------------------------------------
-- Called by PROCESS_ORDER
FUNCTION MATCH_SHIPMENT(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                        O_shipment         IN OUT SHIPMENT.SHIPMENT%TYPE,
                        O_ship_match       IN OUT BOOLEAN,
                        I_asn              IN     SHIPMENT.ASN%TYPE,
                        I_order_no         IN     SHIPMENT.ORDER_NO%TYPE,
                        I_to_loc           IN     SHIPMENT.TO_LOC%TYPE,
                        I_ship_date        IN     SHIPMENT.SHIP_DATE%TYPE,
                        I_est_arr_date     IN     SHIPMENT.EST_ARR_DATE%TYPE,
                        I_message_type     IN     VARCHAR2)
return BOOLEAN IS

   L_appt_status   VARCHAR2(1) := NULL;
   L_status        SHIPMENT.STATUS_CODE%TYPE;
   L_shipment      SHIPMENT.SHIPMENT%TYPE;
   RECORD_LOCKED   EXCEPTION;
   PRAGMA          EXCEPTION_INIT(Record_Locked, -54);

   cursor C_SHIP is
      select shipment
        from shipment
       where order_no  = I_order_no
         and asn = I_asn
         and ship_origin  = '4'
         and status_code  = 'U'
         and to_loc = I_to_loc;

   cursor C_SHIP2 is
      select status_code,
             shipment
        from shipment
       where order_no = I_order_no
         and asn = I_asn
         and ship_origin in ('0', '6')
         and to_loc = I_to_loc;

   cursor C_SHIP_LOCK1 is
      select 'x'
        from shipment
       where order_no  = I_order_no
         and asn = I_asn
         and ship_origin  = '4'
         and status_code  = 'U'
         and to_loc     = I_to_loc
         for update nowait;

   cursor C_SHIP_LOCK2 is
      select 'x'
        from shipment
       where shipment = L_shipment
         for update nowait;

   cursor C_SHIPSKU_LOCK is
      select 'x'
        from shipsku
       where shipment = L_shipment
         for update nowait;

   cursor C_CHECK_APPT_STATUS is
      select /*+ ordered */ 'x'
        from shipment s,
             shipsku sk,
             appt_detail ad,
             appt_head ah
       where ah.loc = I_to_loc
         and s.shipment = sk.shipment
         and s.order_no = I_order_no
         and s.asn = I_asn
         and s.to_loc = I_to_loc
         and s.asn = ad.asn
         and s.to_loc = ah.loc
         and sk.item = ad.item
         and ah.loc = ad.loc
         and ah.appt = ad.appt
         and ah.status != 'AC'
         for update of s.status_code,
                       s.ship_date,
                       s.est_arr_date nowait;
BEGIN
   open C_SHIP;
   fetch C_SHIP into L_shipment;
   close C_SHIP;

   if L_shipment is not NULL then
      O_ship_match := TRUE;
   else
      O_ship_match := FALSE;
   end if;

   if O_ship_match then
      open C_SHIP_LOCK1;
      close C_SHIP_LOCK1;
      -- set shipments status from 'U' unmatched to 'R' received.
      -- Update all shipments that matched - NOT just the first shipment
      -- fetched.
      update shipment
         set status_code = 'R',
             ship_date    = I_ship_date,
             est_arr_date = I_est_arr_date
       where asn = I_asn
         and order_no     = I_order_no
         and to_loc       = I_to_loc
         and ship_origin  = '4'
         and status_code  = 'U';
   else
      open C_SHIP2;
      fetch C_SHIP2 into L_status, L_shipment;
      ---
      if lower(I_message_type) = 'asnincre' then
         -- ASN already exists in the system, reject it if it's a new create message
         if C_SHIP2%FOUND then
            O_error_message := SQL_LIB.GET_MESSAGE_TEXT('DUP_ASN',
                                                  NULL,
                                                  NULL,
                                                  NULL);
            raise PROGRAM_ERROR;
         end if;
      end if;
      ---
      close C_SHIP2;

      -- if a shipment already exists for this order/ASN/location and
      -- it's been received, no updates will be accepted.
      if L_status = 'R' then
         O_error_message := SQL_LIB.GET_MESSAGE_TEXT('NO_UPDATE_SHIP',
                                               NULL,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

      open C_CHECK_APPT_STATUS;
      fetch C_CHECK_APPT_STATUS into L_appt_status;

      -- if appointment status is not closed, reject the record
      if C_CHECK_APPT_STATUS%FOUND then
         O_error_message := SQL_LIB.GET_MESSAGE_TEXT('OPEN_APPTS_ASN',
                                               NULL,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

      close C_CHECK_APPT_STATUS;

      -- If a shipment exists, but hasn't been received, it will
      -- be deleted and replaced with the information on the current ASN.
      if L_status is NOT NULL then
         open C_SHIPSKU_LOCK;
         close C_SHIPSKU_LOCK;

         delete /*+ index (shipsku, pk_shipsku)*/ from shipsku
          where shipment = L_shipment
                and item > ' '
                and seq_no > -1;

         open C_SHIP_LOCK2;
         close C_SHIP_LOCK2;

         delete from shipment
          where shipment = L_shipment;
      end if;
   end if;

   if O_shipment is null then
     O_shipment := L_shipment;
   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when RECORD_LOCKED then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('TABLE_LOCKED',
                                            'shipment',
                                            I_order_no,
                                            I_asn);
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.MATCH_SHIPMENT',
                                            to_char(SQLCODE));
      return FALSE;

END MATCH_SHIPMENT;
-----------------------------------------------------------------------------------
-- Called by PROCESS_ORDER
FUNCTION NEW_SHIPMENT(O_error_message      IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
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
                      I_bill_to_loc        IN     SHIPMENT.BILL_TO_LOC%TYPE,
                      I_bill_to_loc_type   IN     SHIPMENT.BILL_TO_LOC_TYPE%TYPE,
                      I_carton             IN     carton.carton%type,
                      I_order_loc          IN     NUMBER)

return BOOLEAN IS

   L_exists           VARCHAR2(1) := NULL;
   L_phy_wh           SHIPMENT.BILL_TO_LOC%TYPE              := NULL;

   cursor C_ORDLOC is
      select 'Y'
        from ordloc ol,
             store st
       where ol.order_no = I_order_no
         and ol.location = st.store
         and st.store    = I_location
       union all
      select 'Y'
        from ordloc ol,
             wh wh
       where ol.order_no = I_order_no
         and ol.location = wh.wh
         and wh.physical_wh = I_location;

   cursor C_PHY_WH is
      select physical_wh
        from wh
       where wh = I_bill_to_loc;

BEGIN

   open C_ORDLOC;
   fetch C_ORDLOC into L_exists;
   close C_ORDLOC;

   if L_exists is NULL then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('LOC_ORD_NOT_EXIST',
                                            I_location,
                                            I_order_no,
                                            NULL);
      raise PROGRAM_ERROR;
   end if;
   if O_shipment is null then
     if SHIPMENT_ATTRIB_SQL.NEXT_SHIPMENT(O_error_message,
                                          O_shipment) = FALSE then
        raise PROGRAM_ERROR;
     end if;
   End if;

   if L_exists is not NULL then
    if I_bill_to_loc is not NULL then
         open C_PHY_WH;
         fetch C_PHY_WH into L_phy_wh;
         close C_PHY_WH;
      end if;
   end if;

   -- Set the status for the shipment equal to 6 for carton receiving
   -- or to 0 for normal ASN receiving
   insert into shipment(shipment,
                        order_no,
                        bol_no,
                        asn,
                        ship_date,
                        est_arr_date,
                        ship_origin,
                        status_code,
                        invc_match_status,
                        to_loc_type,
                        to_loc,
                        from_loc_type,
                        from_loc,
                        courier,
                        no_boxes,
                        ext_ref_no_in,
                        bill_to_loc,
                        bill_to_loc_type)
                 values(O_shipment,
                        I_order_no,
                        NULL,                                 -- bol_no
                        I_asn,
                        I_shipdate,
                        I_est_arr_date,
                        decode(I_carton_ind, 'C', '6', '0'),
                        'I',                                  -- for Input status
                        'U',                                  -- for Invoice Status
                        I_loc_type,
                        I_location,
                        NULL,                                 -- from loc type
                        NULL,                                 -- from loc
                        I_courier,
                        NULL,
                        I_inbound_bol,
                        DECODE(L_phy_wh, NULL, NVL(I_bill_to_loc, I_location),
                                         L_phy_wh),
                        DECODE(I_bill_to_loc_type, NULL, I_loc_type,
                                                   'M', 'W',
                                                   'X', 'W',
                                                   I_bill_to_loc_type));

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.NEW_SHIPMENT',
                                            to_char(SQLCODE));
      return FALSE;

END NEW_SHIPMENT;
----------------------------------------------------------------------------------------
-- Called by PROCESS_ASN
FUNCTION CREATE_INVOICE(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                        I_shipment         IN     SHIPMENT.SHIPMENT%TYPE,
                        I_supplier         IN     ORDHEAD.SUPPLIER%TYPE,
                        I_ship_match       IN     BOOLEAN)
return BOOLEAN IS

   L_settlement_code   SUPS.SETTLEMENT_CODE%TYPE;
   L_posted            BOOLEAN;

   cursor C_SETTLEMENT_CODE is
      select settlement_code
        from sups
       where supplier = I_supplier;

BEGIN
   if I_ship_match then
      -- if there exists at least one shipment that matches then call
      -- function to create invoice and post that invoice to the invoice
      -- matching ap staging tables.
      -- if more than one shipment exists we use the first shipment number fetched.

      -- call to function checks settlement code internally as well as writing
      -- to ap staging tables, however there will be an external check to save
      -- unnecessary calling of the following package
      -- pass I_item with null to asn_to_invc so that the entire shipment and
      -- its associated items will be invoiced

      open C_SETTLEMENT_CODE;
      fetch C_SETTLEMENT_CODE into L_settlement_code;
      close C_SETTLEMENT_CODE;

      if L_settlement_code = 'E' then
         if NOT INVC_WRITE_SQL.ASN_TO_INVC(O_error_message,
                                           L_posted,
                                           I_shipment,
                                           I_supplier,
                                           'I',
                                           NULL,
                                           NULL,
                                           NULL,
                                           NULL,
                                           NULL,
                                           NULL) then

            raise PROGRAM_ERROR;
         end if;
      end if;
   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
     return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.CREATE_INVOICE',
                                            To_Char(SQLCODE));
      return FALSE;

END CREATE_INVOICE;
-----------------------------------------------------------------------------------
-- Called by CHECK_ITEM
FUNCTION MATCH_ITEM(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                    I_shipment         IN     SHIPMENT.SHIPMENT%TYPE,
                    I_asn              IN     SHIPMENT.ASN%TYPE,
                    I_order_no         IN     SHIPMENT.ORDER_NO%TYPE,
                    I_location         IN     SHIPMENT.TO_LOC%TYPE,
                    I_item             IN     SHIPSKU.ITEM%TYPE,
                    I_ref_item         IN     SHIPSKU.REF_ITEM%TYPE,
                    I_carton           IN     SHIPSKU.CARTON%TYPE,
                    I_qty              IN     SHIPSKU.QTY_EXPECTED%TYPE,
                    I_status_code      IN     SHIPSKU.STATUS_CODE%TYPE,
                    I_unit_cost        IN     ORDLOC.UNIT_COST%TYPE,
                    I_unit_retail      IN     ORDLOC.UNIT_RETAIL%TYPE
                    )
return BOOLEAN IS
   L_seq_no        SHIPSKU.SEQ_NO%TYPE;
   L_retek_item    ITEM_MASTER.ITEM%TYPE;
   L_qty_received  SHIPSKU.QTY_RECEIVED%TYPE;
   L_item_match    BOOLEAN;

   cursor C_MATCH_ITEM is
      select nvl(sum(nvl(sk.qty_received,0)),0)
        from shipment sm,
             shipsku sk
       where sm.shipment     = sk.shipment
         and sm.asn          = I_asn
         and sm.order_no     = I_order_no
         and sm.to_loc       = I_location
         and sm.ship_origin  = '4'
         and sk.item         = I_item;
BEGIN
   L_item_match := FALSE;

   open C_MATCH_ITEM;
   fetch C_MATCH_ITEM into L_qty_received;
   if C_MATCH_ITEM%FOUND then
      L_item_match := TRUE;
   end if;
   close C_MATCH_ITEM;

   if NOT L_item_match then
      P_shipskus_size := P_shipskus_size + 1;
      P_shipments(P_shipskus_size) := I_shipment;
      P_items(P_shipskus_size) := I_item;
      P_distro_nos(P_shipskus_size) := NULL;
      P_ref_items(P_shipskus_size) := I_ref_item;
      P_cartons(P_shipskus_size) := I_carton;
      P_inv_statuses(P_shipskus_size) := -1;
      P_status_codes(P_shipskus_size) := I_status_code;
      P_qty_receiveds(P_shipskus_size) := NULL;
      P_unit_costs(P_shipskus_size) := I_unit_cost;
      P_unit_retails(P_shipskus_size) := I_unit_retail;
      P_qty_expecteds(P_shipskus_size) := I_qty;

   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
     return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.MATCH_ITEM',
                                            To_Char(SQLCODE));
      return FALSE;

END MATCH_ITEM;
-----------------------------------------------------------------------------------
-- Called by PROCESS_ASN
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
return BOOLEAN IS

   L_seq_no       SHIPSKU.SEQ_NO%TYPE;
   L_retek_item   ITEM_MASTER.ITEM%TYPE      := NULL;
   L_on_order     ORDHEAD.ORDER_NO%TYPE      := NULL;
   L_on_alloc     ALLOC_HEADER.ORDER_NO%TYPE := NULL;
   L_unit_cost    ORDLOC.UNIT_COST%TYPE      := NULL;
   L_unit_retail  ORDLOC.UNIT_RETAIL%TYPE    := NULL;
   L_qty_ordered  ORDLOC.QTY_ORDERED%TYPE    := 0;
   L_qty_received ORDLOC.QTY_RECEIVED%TYPE   := 0;
   L_status_code  SHIPSKU.STATUS_CODE%TYPE   := NULL;
   L_exist        NUMBER                     := NULL;

   cursor C_VALID_ITEM is
      select 1
        from item_master
       where item   = I_item
         and item_level = tran_level
         and status = 'A';

   -- This doesn't need to check the status of the item
   -- because an unapproved item couldn't be on an order
   cursor C_VPN_ITEM is
      select its.item
        from item_supplier its,
             item_master im,
             ordhead oh
       where its.supplier     = oh.supplier
         and oh.order_no      = I_order_no
         and its.vpn          = I_vpn
         and its.item         = I_item
         and its.item         = im.item
         and im.tran_level    = im.item_level;

   cursor C_VPN_ITEM_ORDER_STORE is
       select /*+ ordered */ol.order_no,
              ol.unit_cost,
              ol.unit_retail,
              ol.qty_ordered,
              ol.qty_received
         from store st,
              ordloc ol
        where ol.item          = L_retek_item
          and ol.order_no      = I_order_no
          and ol.location      = st.store
          and st.store         = I_location;

   cursor C_VPN_ITEM_ORDER_WH is
       select /*+ ordered */ol.order_no,
              ol.unit_cost,
              ol.unit_retail,
              SUM(ol.qty_ordered),
              SUM(ol.qty_received)
         from wh wh,
              ordloc ol
        where ol.item           = L_retek_item
          and ol.order_no       = I_order_no
          and ol.location       = wh.wh
          and wh.physical_wh    = I_location
        GROUP BY ol.order_no,
                 ol.unit_cost,
                 ol.unit_retail;

   cursor C_ALLOC is
      select alloc_header.order_no
        from alloc_header,
             alloc_detail,
             wh wh,
             wh w2
       where alloc_header.order_no = I_order_no
         and alloc_header.item = L_retek_item
         and alloc_header.wh = wh.wh
         and wh.physical_wh = I_location
         --
         and alloc_detail.to_loc =  nvl(w2.wh, NVL(I_alloc_loc, alloc_detail.to_loc))
         and w2.wh (+) = alloc_detail.to_loc
         and w2.physical_wh (+) = I_alloc_loc
         --
         and alloc_header.alloc_no = alloc_detail.alloc_no
       GROUP BY alloc_header.order_no;

   cursor C_ITEM_ORDER_STORE is
       select /*+ ordered index(ol PK_ORDLOC) */ ol.order_no,
              ol.unit_cost,
              ol.unit_retail,
              ol.qty_ordered,
              ol.qty_received
         from store st,
              ordloc ol
        where ol.item          = L_retek_item
          and ol.order_no      = I_order_no
          and ol.location      = st.store
          and st.store         = I_location;

   cursor C_ITEM_ORDER_WH is
      SELECT /*+ ordered index(ol PK_ORDLOC) */ ol.order_no,
             ol.unit_cost,
             ol.unit_retail,
             SUM(ol.qty_ordered),
             SUM(ol.qty_received)
        from wh wh,
             ordloc ol
       where ol.item           = L_retek_item
         and ol.order_no       = I_order_no
         and ol.location       = wh.wh
         and wh.physical_wh    = I_location
    GROUP BY ol.order_no,
             ol.unit_cost,
             ol.unit_retail;

   -- This doesn't need to check the status of the item
   -- because an unapproved item couldn't be on an order
   cursor C_REF_ITEM is
       select im.item_parent
         from item_master im
        where im.item = I_ref_item;

    -- This doesn't need to check the status of the item
    -- because an unapproved item couldn't be on an order

   cursor C_REF_ITEM_ORDER_STORE is
       select /*+ ordered */ol.order_no,
              ol.unit_cost,
              ol.unit_retail,
              ol.qty_ordered,
              ol.qty_received
         from store st,
              ordloc ol
        where ol.item          = L_retek_item
          and ol.order_no      = I_order_no
          and ol.location      = st.store
          and st.store         = I_location;

   cursor C_REF_ITEM_ORDER_WH is
       select /*+ ordered */ol.order_no,
              ol.unit_cost,
              ol.unit_retail,
              SUM(ol.qty_ordered),
              SUM(ol.qty_received)
         from wh wh,
              ordloc ol
        where ol.item           = L_retek_item
          and ol.order_no       = I_order_no
          and ol.location       = wh.wh
          and wh.physical_wh    = I_location
    GROUP BY ol.order_no,
             ol.unit_cost,
             ol.unit_retail;


BEGIN
   if I_vpn is NOT NULL then
      open C_VPN_ITEM;
      fetch C_VPN_ITEM into L_retek_item;
      close C_VPN_ITEM;

      if L_retek_item is NULL then
         O_error_message := SQL_LIB.CREATE_MSG('VPN_INV_FOR_ORDER',
                                               I_vpn,
                                               I_order_no,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

      -- Fetch order information, if it exists, for the VPN's ITEM
      if I_loc_type = 'S' then
         open C_VPN_ITEM_ORDER_STORE;
         fetch C_VPN_ITEM_ORDER_STORE into L_on_order,
                                           L_unit_cost,
                                           L_unit_retail,
                                           L_qty_ordered,
                                           L_qty_received;
         close C_VPN_ITEM_ORDER_STORE;
      else
         open C_VPN_ITEM_ORDER_WH;
         fetch C_VPN_ITEM_ORDER_WH into L_on_order,
                                        L_unit_cost,
                                        L_unit_retail,
                                        L_qty_ordered,
                                        L_qty_received;
         close C_VPN_ITEM_ORDER_WH;
      end if;

      if L_on_order is NULL then
         -- item is valid but not on order
         O_error_message := SQL_LIB.CREATE_MSG('NO_SKU_ORDER',
                                               L_retek_item,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

   elsif I_ref_item is NOT NULL then
      -- supplier has returned item as REF_ITEM
      open C_REF_ITEM;
      fetch C_REF_ITEM into L_retek_item;
      close C_REF_ITEM;

      if L_retek_item is NULL then
         O_error_message := SQL_LIB.CREATE_MSG('INV_REF_ITEM',
                                               NULL,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

      if I_loc_type = 'S' then
         open C_REF_ITEM_ORDER_STORE;
         fetch C_REF_ITEM_ORDER_STORE into L_on_order,
                                           L_unit_cost,
                                           L_unit_retail,
                                           L_qty_ordered,
                                           L_qty_received;
         close C_REF_ITEM_ORDER_STORE;
      else
         open C_REF_ITEM_ORDER_WH;
         fetch C_REF_ITEM_ORDER_WH into L_on_order,
                                        L_unit_cost,
                                        L_unit_retail,
                                        L_qty_ordered,
                                        L_qty_received;
         close C_REF_ITEM_ORDER_WH;
      end if;

      if L_on_order is NULL then
         -- item is valid but not on order
         O_error_message := SQL_LIB.CREATE_MSG('NO_SKU_ORDER',
                                               L_retek_item,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

   elsif I_item is NOT NULL then
      -- supplier has returned item as Retek ITEM
      L_retek_item := I_item;

      if I_loc_type = 'S' then
         open C_ITEM_ORDER_STORE;
         fetch C_ITEM_ORDER_STORE into L_on_order,
                                       L_unit_cost,
                                       L_unit_retail,
                                       L_qty_ordered,
                                       L_qty_received;
         close C_ITEM_ORDER_STORE;
      else
         open C_ITEM_ORDER_WH;
         fetch C_ITEM_ORDER_WH into L_on_order,
                                    L_unit_cost,
                                    L_unit_retail,
                                    L_qty_ordered,
                                    L_qty_received;
         close C_ITEM_ORDER_WH;
      end if;

      open C_VALID_ITEM;
      fetch C_VALID_ITEM into L_exist;
      close C_VALID_ITEM;

      if L_on_order is NULL then
         if L_exist is NULL then
            O_error_message := SQL_LIB.CREATE_MSG('INV_ITEM',
                                                  NULL,
                                                  NULL,
                                                  NULL);
            raise PROGRAM_ERROR;
         end if;

         -- item is valid but not on order
         O_error_message := SQL_LIB.CREATE_MSG('NO_SKU_ORDER',
                                               L_retek_item,
                                               NULL,
                                               NULL);
         raise PROGRAM_ERROR;
      end if;

   else -- we didn't get item, ref_item or VPN
      O_error_message := SQL_LIB.CREATE_MSG('INV_SYSTEM_IND',
                                            NULL,
                                            NULL,
                                            NULL);
      raise PROGRAM_ERROR;
   end if;

   -- if pre_mark_ind is set, check allocation location here
   if I_premark_ind = 'Y' then
      open C_ALLOC;
      fetch C_ALLOC into L_on_alloc;
      close C_ALLOC;

      if L_on_alloc is NULL then
         O_error_message := SQL_LIB.CREATE_MSG('ITEM_LOC_ALLOC',
                                               L_retek_item,
                                               I_location,
                                               I_order_no);
         raise PROGRAM_ERROR;
      end if;
   end if;

   if (L_qty_ordered - L_qty_received) < I_qty then
      L_status_code := 'H';
   else
      L_status_code := 'A';
   end if;

   if I_ship_match then
      if MATCH_ITEM(O_error_message,
                    I_shipment,
                    I_asn,
                    I_order_no,
                    I_location,
                    L_retek_item,
                    I_ref_item,
                    I_carton,
                    I_qty,
                    L_status_code,
                    L_unit_cost,
                    L_unit_retail) = FALSE then
         raise PROGRAM_ERROR;
      end if;
   else

      P_shipskus_size := P_shipskus_size + 1;
      P_shipments(P_shipskus_size) := I_shipment;
      P_items(P_shipskus_size) := L_retek_item;
      P_distro_nos(P_shipskus_size) := NULL;
      P_ref_items(P_shipskus_size) := I_ref_item;
      P_cartons(P_shipskus_size) := I_carton;
      P_inv_statuses(P_shipskus_size) := -1;
      P_status_codes(P_shipskus_size) := L_status_code;
      P_qty_receiveds(P_shipskus_size) := NULL;
      P_unit_costs(P_shipskus_size) := L_unit_cost;
      P_unit_retails(P_shipskus_size) := L_unit_retail;
      P_qty_expecteds(P_shipskus_size) := I_qty;
   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            'ASN_SQL.CHECK_ITEM',
                                            To_Char(SQLCODE));
      return FALSE;

END CHECK_ITEM;
-----------------------------------------------------------------------------------
-- Called by PROCESS_ASN
FUNCTION VALIDATE_CARTON(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                         I_carton           IN     CARTON.CARTON%TYPE,
                         I_alloc_loc        IN     CARTON.LOCATION%TYPE)
return BOOLEAN IS

   L_carton_location  CARTON.LOCATION%TYPE;
   L_alloc_loc_type   SHIPMENT.TO_LOC_TYPE%TYPE;

   cursor C_CARTON is
      select location
        from carton
       where carton = I_carton;

BEGIN
   -- validate allocation location
   if I_alloc_loc is NOT NULL then
      if VALIDATE_LOCATION(O_error_message,
                           L_alloc_loc_type,
                           I_alloc_loc) = FALSE then
          raise PROGRAM_ERROR;
      end if;
      ---
      open C_CARTON;
      fetch C_CARTON into L_carton_location;
      close C_CARTON;
      ---
      if L_carton_location is NULL then
         insert into carton(carton,
                            loc_type,
                            location)
                     values(I_carton,
                            L_alloc_loc_type,
                            I_alloc_loc);
      else
         if L_carton_location != I_alloc_loc then
            O_error_message := SQL_LIB.GET_MESSAGE_TEXT('CARTON_LOC', NULL, NULL, NULL);
            raise PROGRAM_ERROR;
        end if;
     end if;
  end if;

  return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.VALIDATE_CARTON',
                                            To_Char(SQLCODE));
      return FALSE;

END VALIDATE_CARTON;
--------------------------------------------------------------------------------------------------------------------
--  Called from PROCESS_ASN
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
return BOOLEAN IS

   L_import_id     ORDHEAD.IMPORT_ID%TYPE;
   L_import_type   ORDHEAD.IMPORT_TYPE%TYPE;

BEGIN

   if VALIDATE_ORDER(O_error_message,
                     O_order_no,
                     O_pre_mark_ind,
                     L_import_id,
                     L_import_type,
                     I_order_no,
                     I_ship_pay_method,
                     I_not_after_date,
                     I_supplier) = FALSE then
      raise PROGRAM_ERROR;
   end if;

    if MATCH_SHIPMENT(O_error_message,
                      O_shipment,
                      O_ship_match,
                      I_asn,
                      O_order_no,
                      I_to_loc,
                      I_ship_date,
                      I_est_arr_date,
                      I_message_type) = FALSE then
       raise PROGRAM_ERROR;
    end if;

   if NOT O_ship_match then
      if NEW_SHIPMENT(O_error_message,
                      O_shipment,
                      I_asn,
                      O_order_no,
                      I_to_loc,
                      I_to_loc_type,
                      I_ship_date,
                      I_est_arr_date,
                      I_carton_ind,
                      I_inbound_bol,
                      I_courier,
                      L_import_id,
                      L_import_type,
                      I_carton,
                      I_order_loc) = FALSE then
         raise PROGRAM_ERROR;
      end if;
   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.PROCESS_ORDER',
                                            to_char(SQLCODE));
      return FALSE;

END PROCESS_ORDER;
--------------------------------------------------------------------------------------------
FUNCTION DELETE_ASN(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                    I_asn              IN     SHIPMENT.ASN%TYPE)
return BOOLEAN IS

   L_rowid  ROWID;

   cursor C_SHIP is
      select status_code,
             shipment
        from shipment
       where asn = I_asn
         and ship_origin in ('0', '6');

   cursor C_CARTON_LOCK (L_shipment SHIPMENT.SHIPMENT%TYPE) is
      select 'x'
        from carton c
       where exists (select 'x'
                       from shipsku sk
                      where sk.shipment = L_shipment
                        and sk.carton = c.carton)
         for update nowait;

   cursor C_INVC_XREF_LOCK (L_shipment SHIPMENT.SHIPMENT%TYPE) is
      select 'x'
        from invc_xref
       where shipment = L_shipment
         for update nowait;

   cursor C_SHIP_LOCK (L_shipment SHIPMENT.SHIPMENT%TYPE) is
      select rowid
        from shipment
       where shipment = L_shipment
         for update nowait;

   cursor C_SHIPSKU_LOCK (L_shipment SHIPMENT.SHIPMENT%TYPE) is
      select 'x'
        from shipsku
       where shipment = L_shipment
         for update nowait;

   L_table         VARCHAR2(255);

   RECORD_LOCKED   EXCEPTION;
   PRAGMA          EXCEPTION_INIT(Record_Locked, -54);
BEGIN

   for c_rec in C_SHIP LOOP
      if c_rec.status_code = 'R' then
         O_error_message := SQL_LIB.GET_MESSAGE_TEXT('NO_UPDATE_SHIP',
                                                NULL,
                                                NULL,
                                                NULL);
         raise PROGRAM_ERROR;
         ---
         exit;
         ---
      else
         L_table := 'INVC_XREF';
         open C_INVC_XREF_LOCK (c_rec.shipment);
         close C_INVC_XREF_LOCK;
         ---
         delete from invc_xref
          where shipment = c_rec.shipment;
         ---
         L_table := 'CARTON';
         open C_CARTON_LOCK (c_rec.shipment);
         close C_CARTON_LOCK;
         ---
         delete from carton c
          where exists(select 'x'
                         from shipsku sk
                        where sk.shipment = c_rec.shipment
                          and sk.carton = c.carton);
         ---
         L_table := 'SHIPSKU';
         open C_SHIPSKU_LOCK (c_rec.shipment);
         close C_SHIPSKU_LOCK;
         ---
         delete /*+ index (shipsku, pk_shipsku)*/ from shipsku
          where shipment = c_rec.shipment
                and item > ' '
                and seq_no > -1;
         ---
         L_table := 'SHIPMENT';
         open C_SHIP_LOCK (c_rec.shipment);
         fetch C_SHIP_LOCK into L_rowid;
         close C_SHIP_LOCK;
         ---
         delete from shipment
          where rowid = L_rowid;
         ---
      end if;
   end LOOP;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when RECORD_LOCKED then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('TABLE_LOCKED',
                                            L_table,
                                            I_asn,
                                            NULL);
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.DELETE_ASN',
                                            to_char(SQLCODE));
      return FALSE;

END DELETE_ASN;
--------------------------------------------------------------------------------------------
FUNCTION DO_SHIPSKU_INSERTS(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE)
return BOOLEAN IS
   L_seq_no SHIPSKU.SEQ_NO%TYPE := 1;
BEGIN
   for i in 1..P_shipskus_size LOOP
      P_seq_nos(i) := L_seq_no;
      L_seq_no := L_seq_no + 1;
   end LOOP;

   FORALL i in 1..P_shipskus_size
      insert into shipsku(shipment,
                          seq_no,
                          item,
                          distro_no,
                          distro_type, --OLR V1.00 Inserted
                          ref_item,
                          carton,
                          inv_status,
                          status_code,
                          qty_received,
                          unit_cost,
                          unit_retail,
                          qty_expected)
                   values(P_shipments(i),
                          P_seq_nos(i),
                          P_items(i),
                          P_distro_nos(i),
                          decode(P_distro_nos(i),null,null,'A'),--OLR V1.00 Inserted
                          P_ref_items(i),
                          P_cartons(i),
                          P_inv_statuses(i),
                          P_status_codes(i),
                          P_qty_receiveds(i),
                          P_unit_costs(i),
                          P_unit_retails(i),
                          P_qty_expecteds(i));

   P_shipskus_size := 0;
   return TRUE;
EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.DO_SHIPSKU_INSERTS',
                                            to_char(SQLCODE));
      return FALSE;

END DO_SHIPSKU_INSERTS;
--------------------------------------------------------------------------------------------
FUNCTION RESET_GLOBALS(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE)
return BOOLEAN
IS
BEGIN
   P_shipments.DELETE;
   P_seq_nos.DELETE;
   P_items.DELETE;
   P_distro_nos.DELETE;
   P_ref_items.DELETE;
   P_cartons.DELETE;
   P_inv_statuses.DELETE;
   P_status_codes.DELETE;
   P_qty_receiveds.DELETE;
   P_unit_costs.DELETE;
   P_unit_retails.DELETE;
   P_qty_expecteds.DELETE;

   P_shipskus_size := 0;

   return true;
EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.RESET_GLOBALS',
                                            to_char(SQLCODE));
      return FALSE;
END RESET_GLOBALS;
--------------------------------------------------------------------------------------------
--  Called from SHIPMENT_SQL.SHIP_PO
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
return BOOLEAN IS

   L_import_id     ORDHEAD.IMPORT_ID%TYPE;
   L_import_type   ORDHEAD.IMPORT_TYPE%TYPE;

BEGIN

   if VALIDATE_ORDER(O_error_message,
                     O_order_no,
                     O_pre_mark_ind,
                     L_import_id,
                     L_import_type,
                     I_order_no,
                     I_ship_pay_method,
                     I_not_after_date,
                     I_supplier) = FALSE then
      raise PROGRAM_ERROR;
   end if;

   if NEW_SHIPMENT_ONLINE(O_error_message,
                          O_shipment,
                          I_asn,
                          O_order_no,
                          I_to_loc,
                          I_to_loc_type,
                          I_ship_date,
                          I_est_arr_date,
                          I_carton_ind,
                          I_inbound_bol,
                          I_courier,
                          I_no_boxes,
                          I_comments,
                          L_import_id,
                          L_import_type) = FALSE then
      raise PROGRAM_ERROR;
   end if;

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.PROCESS_ORDER_ONLINE',
                                            to_char(SQLCODE));
      return FALSE;

END PROCESS_ORDER_ONLINE;
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
return BOOLEAN IS

   L_exists             VARCHAR2(1) := NULL;
   L_phy_wh             SHIPMENT.BILL_TO_LOC%TYPE              := NULL;

    cursor C_ORDLOC_STORE is
       select 'Y'
         from ordloc ol,
              store st
        where ol.order_no      = I_order_no
          and ol.location      = st.store
          and st.store         = I_location;

    cursor C_ORDLOC_WH is
       select 'Y'
         from ordloc ol,
              wh wh
        where ol.order_no       = I_order_no
          and ol.location       = wh.wh
          and wh.physical_wh    = I_location;

    cursor C_PHY_WH is
       select physical_wh
         from wh
        where wh = I_bill_to_loc;

BEGIN

   if I_loc_type = 'S' then
      open C_ORDLOC_STORE;
      fetch C_ORDLOC_STORE into L_exists;
      close C_ORDLOC_STORE;
   end if;

   if I_loc_type = 'W' then
      open C_ORDLOC_WH;
      fetch C_ORDLOC_WH into L_exists;
      close C_ORDLOC_WH;
   end if;

   if L_exists is NULL then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('LOC_ORD_NOT_EXIST',
                                            I_location,
                                            I_order_no,
                                            NULL);
      raise PROGRAM_ERROR;
   end if;

   if SHIPMENT_ATTRIB_SQL.NEXT_SHIPMENT(O_error_message,
                                        O_shipment) = FALSE then
      raise PROGRAM_ERROR;
   end if;

   if L_exists is not NULL then
      if I_bill_to_loc is not NULL then
         open C_PHY_WH;
         fetch C_PHY_WH into L_phy_wh;
         close C_PHY_WH;
      end if;
   end if;

   -- Origin is always 1 - Manual Shipment for orders shipped online
   insert into shipment(shipment,
                        order_no,
                        bol_no,
                        asn,
                        ship_date,
                        est_arr_date,
                        ship_origin,
                        status_code,
                        invc_match_status,
                        to_loc_type,
                        to_loc,
                        from_loc_type,
                        from_loc,
                        courier,
                        no_boxes,
                        comments,
                        ext_ref_no_in,
                        bill_to_loc,
                        bill_to_loc_type)
                 values(O_shipment,
                        I_order_no,
                        NULL,   -- bol_no
                        I_asn,
                        I_shipdate,
                        I_est_arr_date,
                        1,                     -- for Ship origin
                        'I',                   -- for Input status
                        'U',                   -- for Invoice Status
                        I_loc_type,
                        I_location,
                        NULL,                  -- from loc type
                        NULL,                  -- from loc
                        I_courier,
                        I_no_boxes,
                        I_comments,
                        I_inbound_bol,
                        DECODE(L_phy_wh, NULL, NVL(I_bill_to_loc, I_location),
                                         L_phy_wh),
                        DECODE(I_bill_to_loc_type, NULL, I_loc_type,
                                                   'M', 'W',
                                                   'X', 'W',
                                                   I_bill_to_loc_type));

   return TRUE;

EXCEPTION
   when PROGRAM_ERROR then
      return FALSE;

   when OTHERS then
      O_error_message := SQL_LIB.GET_MESSAGE_TEXT('PACKAGE_ERROR',
                                            SQLERRM,
                                            'SMR_LEAP_ASN_SQL.NEW_SHIPMENT_ONLINE',
                                            to_char(SQLCODE));
      return FALSE;

END NEW_SHIPMENT_ONLINE;
--------------------------------------------------------------------------------------------
END SMR_LEAP_ASN_SQL;
/