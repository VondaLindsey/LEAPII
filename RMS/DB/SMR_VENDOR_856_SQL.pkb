

CREATE OR REPLACE PACKAGE BODY RMS13.SMR_VENDOR_856_SQL IS
-- Module Name: SMR_VENDOR_856_SQL
-- Description: This package is used to validate the vendor 856 files
--              AND load the data into the base shipment/shipsku tables.
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== =========================================
-- 1.00    23-Jun-11 P.Dinsdale  ENH27    OLR initial version.
-- 1.02    20-Feb-12 P.Dinsdale  ENH27    Multiple changes inclduing adding partner
--                                        field and changes to error validation.
-- 1.03    11-OCT-12 V.Ploshko   IMS129679 Removed stand-alone WH 901 hard coding
-- 1.04    15-Mar-13 G.Boyle     CR0001   Removed checks of STORE_CLOSE_DATE
-- 1.05    08-Sep-14 C.Raghu     ME375548 For soft error with error Code 99 in asn error file
--                                        there must be a record for that shipment
--                                        in the asn no error file.
--------------------------------------------------------------------------------

-----------------------------------------------------------------------------------
--PRIVATE FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Procedure Name: SHO
-- Purpose: Used for debug purposes
--------------------------------------------------------------------------------
PROCEDURE SHO(O_ERROR_MESSAGE IN VARCHAR2) IS
  L_DEBUG_ON BOOLEAN := false; -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
BEGIN

  IF L_DEBUG_ON THEN
    dbms_output.put_line('DEBUG:' || to_char(sysdate, 'HH24:MI:SS') || ':' ||O_ERROR_MESSAGE);
  END IF;

END;

--------------------------------------------------------------------------------
-- Procedure Name: F_DELETE_ERRORED_RECORDS
-- Purpose: Deletes all records with errrors so that we do not try to make ASNs
--          with them
--------------------------------------------------------------------------------
FUNCTION F_DELETE_ERRORED_RECORDS(O_error_message IN OUT VARCHAR2)
  RETURN BOOLEAN IS
  L_program VARCHAR2(61) := package_name || '.F_DELETE_ERRORED_RECORDS';
BEGIN

  sho(L_program);

  DELETE FROM smr_856_vendor_item_2 I
   WHERE asn IS NULL
      OR partner IS NULL
      OR EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = I.asn
                    AND partner = I.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'H');

  DELETE FROM smr_856_vendor_item I
   WHERE asn IS NULL
      OR partner IS NULL
      OR EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = I.asn
                    AND partner = I.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'H');

  DELETE FROM smr_856_vendor_order O
   WHERE asn IS NULL
      OR partner IS NULL
      OR EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = O.asn
                    AND partner = O.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'H');

  DELETE FROM smr_856_vendor_asn A
   WHERE asn IS NULL
      OR partner IS NULL
      OR EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = A.asn
                    AND partner = A.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'H');

  --delete soft errors that should not be processed in RMS
  DELETE FROM smr_856_vendor_item_2 I
   WHERE EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = I.asn
                    AND partner = I.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'S'
                    AND error_value like 'Duplicate carton #'||I.carton);

  DELETE FROM smr_856_vendor_item I
   WHERE EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = I.asn
                    AND partner = I.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'S'
                    AND error_value like 'Duplicate carton #%'||I.carton);

  DELETE FROM smr_856_vendor_order O
   WHERE EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = O.asn
                    AND partner = O.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'S'
                    AND error_value like 'Duplicate carton #%'
                    and not exists (select 'x' from smr_856_vendor_item_2 I2
                                     where I2.ASN       = O.ASN
                                       and I2.ORDER_NO  = O.ORDER_NO
                                       and I2.ORDER_LOC = O.ORDER_LOC
                    ));

  DELETE FROM smr_856_vendor_asn A
   WHERE EXISTS (SELECT 'x'
                   FROM smr_856_vendor_errors
                  WHERE asn = A.asn
                    AND partner = A.partner
                    AND fail_date = P_fail_date
                    AND error_type = 'S'
                    AND error_value like 'Duplicate carton #%'
                    and not exists (select 'x' from smr_856_vendor_item_2 I2
                                     where I2.ASN       = A.ASN
                    ));

  RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_DELETE_ERRORED_RECORDS;

--------------------------------------------------------------------------------
-- Procedure Name: PARSE_CARTON
-- Purpose: Put carton details into O_carton_record. Copied FROM RMSSUB_ASNIN
--------------------------------------------------------------------------------
FUNCTION PARSE_CARTON(O_error_message OUT VARCHAR2,
                      O_carton_record IN OUT nocopy carton_table,
                      I_container_id  IN carton.carton%TYPE,
                      I_location      IN carton.location%TYPE,
                      I_asn_no        IN shipment.asn%TYPE,
                      I_order_no      IN shipment.order_no%TYPE)
  RETURN BOOLEAN IS
  L_program VARCHAR2(61) := package_name || '.PARSE_CARTON';
  k         NUMBER;
BEGIN
  k := (O_carton_record.COUNT);
  k := k + 1;

  O_carton_record(k).asn := TO_CHAR(I_asn_no);
  O_carton_record(k).po_num := I_order_no;
  O_carton_record(k).carton_num := TO_CHAR(I_container_id);
  O_carton_record(k).location := I_location;

  RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          to_char(SQLCODE));
    RETURN FALSE;
END PARSE_CARTON;

--------------------------------------------------------------------------------
-- Procedure Name: PARSE_ITEM
-- Purpose: Put item details into O_item_record. Copied FROM RMSSUB_ASNIN
--------------------------------------------------------------------------------
FUNCTION PARSE_ITEM(O_error_message          OUT VARCHAR2,
                    O_item_record         IN OUT nocopy item_table,
                    I_item_item_id        IN     ordloc.item%TYPE,
                    I_item_unit_qty       IN     ordloc.qty_ordered%TYPE,
                    I_item_ref_item       IN     ordsku.ref_item%TYPE,
                    I_item_vpn            IN     ordloc.item%TYPE,
                    I_item_final_location IN     ordhead.location%TYPE,
                    I_asn_no              IN     shipment.asn%TYPE,
                    I_order_no            IN     shipment.order_no%TYPE,
                    I_carton_no           IN     carton.carton%TYPE)
  RETURN BOOLEAN IS
  L_program          VARCHAR2(61) := package_name || '.PARSE_ITEM';
  j                  NUMBER;
  L_exists           VARCHAR2(1);
  L_supp_pack_exists BOOLEAN;
  L_container_item   item_master.item%TYPE;
  L_sup_qty_level    sups.sup_qty_level%TYPE;
  L_unit_qty         NUMBER(12, 4);
  L_supp_pack_size   ORDSKU.SUPP_PACK_SIZE%TYPE;

  CURSOR C_GET_SUP_QTY_LEVEL is
    SELECT s.sup_qty_level
      FROM ordhead oh, sups s
     WHERE oh.order_no = I_order_no
       AND s.supplier = oh.supplier;

BEGIN

  SQL_LIB.SET_MARK('OPEN',
                   'C_GET_SUP_QTY_LEVEL',
                   'SUPS',
                   'Order No.: ' || I_order_no);
  OPEN C_GET_SUP_QTY_LEVEL;

  SQL_LIB.SET_MARK('FETCH',
                   'C_GET_SUP_QTY_LEVEL',
                   'SUPS',
                   'Order No.: ' || I_order_no);
  FETCH C_GET_SUP_QTY_LEVEL
    into L_sup_qty_level;

  IF L_sup_qty_level IS NULL THEN
    O_error_message := SQL_LIB.CREATE_MSG('NO_DATA_FOUND',
                                          NULL,
                                          NULL,
                                          NULL);
    RETURN FALSE;
  END IF;

  SQL_LIB.SET_MARK('CLOSE',
                   'C_GET_SUP_QTY_LEVEL',
                   'SUPS',
                   'Order No.: ' || I_order_no);
  CLOSE C_GET_SUP_QTY_LEVEL;

  IF L_sup_qty_level = 'CA' THEN
    IF ORDER_ITEM_ATTRIB_SQL.GET_SUPP_PACK_SIZE(O_error_message,
                                                L_supp_pack_exists,
                                                L_supp_pack_size,
                                                I_order_no,
                                                I_item_item_id) = FALSE then
      RETURN FALSE;
    END IF;

    L_unit_qty := NVL(L_supp_pack_size, 1) * I_item_unit_qty;
  ELSE
    L_unit_qty := I_item_unit_qty;
  END IF;

  j := (O_item_record.COUNT);
  j := j + 1;

  O_item_record(j).asn := I_asn_no;
  O_item_record(j).po_num := I_order_no;
  O_item_record(j).carton_num := I_carton_no;
  O_item_record(j).item := I_item_item_id;
  O_item_record(j).ref_item := I_item_ref_item;
  O_item_record(j).vpn := I_item_vpn;
  O_item_record(j).alloc_loc := I_item_final_location;
  O_item_record(j).qty_shipped := L_unit_qty;

  IF ITEM_ATTRIB_SQL.CONTENTS_ITEM_EXISTS(O_error_message,
                                          L_exists,
                                          I_item_item_id) = FALSE then
    RETURN FALSE;
  END IF;

  if L_exists = 'Y' then
    O_error_message := SQL_LIB.CREATE_MSG('SA_CANT_USE_DEPOSIT_CONTR',
                                          NULL,
                                          NULL,
                                          NULL);
    RETURN FALSE;
  end if;

  IF ITEM_ATTRIB_SQL.GET_CONTAINER_ITEM(O_error_message,
                                        L_container_item,
                                        I_item_item_id) = FALSE then
    RETURN FALSE;
  END IF;

  IF L_container_item IS NOT NULL THEN

    j := (O_item_record.COUNT);
    j := j + 1;

    O_item_record(j).asn := I_asn_no;
    O_item_record(j).po_num := I_order_no;
    O_item_record(j).carton_num := I_carton_no;
    O_item_record(j).item := L_container_item;
    O_item_record(j).ref_item := I_item_ref_item;
    O_item_record(j).vpn := I_item_vpn;
    O_item_record(j).alloc_loc := I_item_final_location;
    O_item_record(j).qty_shipped := I_item_unit_qty;

  END IF;

  RETURN TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          to_char(SQLCODE));
    RETURN FALSE;

END PARSE_ITEM;

----------------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Procedure Name: PROCESS_ASN
-- Purpose: Creates shipment records based on the info passed in
--------------------------------------------------------------------------------
FUNCTION PROCESS_ASN(O_error_message OUT VARCHAR2,
                     I_asn           IN asn_record,
                     I_order         IN order_record,
                     I_cartontable   IN carton_table,
                     I_itemtable     IN item_table,
                     I_message_type  IN varchar2,
                     I_order_loc     IN NUMBER)

 RETURN BOOLEAN IS
  L_program     VARCHAR2(61) := package_name || '.PROCESS_ASN';
  L_exists      BOOLEAN := TRUE;
  L_loc_type    SHIPMENT.TO_LOC_TYPE%TYPE;
  L_shipment    SHIPMENT.SHIPMENT%TYPE;
  L_order_no    ORDHEAD.ORDER_NO%TYPE;
  L_premark_ind ORDHEAD.PRE_MARK_IND%TYPE;
  L_ship_match  BOOLEAN;

  L_asn_destination number := null;
BEGIN

  sho(L_program);

  IF SMR_ASN_SQL.RESET_GLOBALS(O_error_message) = FALSE then
    RETURN FALSE;
  END IF;

  ---
  IF SMR_ASN_SQL.VALIDATE_LOCATION(O_error_message,
                                   L_loc_type,
                                   I_asn.destination) = FALSE THEN
    RETURN FALSE;
  END IF;
  ---

  IF SMR_ASN_SQL.PROCESS_ORDER(O_error_message,
                               L_order_no,
                               L_premark_ind,
                               L_shipment,
                               L_ship_match,
                               I_asn.asn,
                               I_order.po_num,
                               I_asn.destination,
                               L_loc_type,
                               I_asn.ship_pay_method,
                               I_order.not_after_date,
                               I_asn.ship_date,
                               I_asn.est_arr_date,
                               I_asn.carrier,
                               I_asn.inbound_bol,
                               I_asn.supplier,
                               I_asn.carton_ind,
                               I_message_type,
                               I_order_loc,
                               I_asn.carton) = FALSE then
    RETURN FALSE;
  END IF;
  ---

  IF I_asn.carton_ind = 'C' THEN
    IF I_cartontable IS NOT NULL THEN
      FOR k IN 1 .. I_cartontable.COUNT LOOP
        IF SMR_ASN_SQL.VALIDATE_CARTON(O_error_message,
                                       I_cartontable(k).carton_num,
                                       I_cartontable(k).location) = FALSE THEN
          RETURN FALSE;
        END IF;
      END LOOP;
    END IF;
  END IF;
  ---

  L_asn_destination := I_asn.destination;

  FOR i IN 1 .. I_itemtable.COUNT LOOP

    if SMR_ASN_SQL.CHECK_ITEM(O_error_message,
                              L_shipment,
                              I_asn.supplier,
                              I_itemtable(i).asn,
                              L_order_no,
                              L_asn_destination,
                              I_itemtable(i).alloc_loc,
                              I_itemtable(i).item,
                              I_itemtable(i).ref_item,
                              I_itemtable(i).vpn,
                              I_itemtable(i).carton_num,
                              L_premark_ind,
                              I_itemtable(i).qty_shipped,
                              L_ship_match,
                              L_loc_type) = FALSE then
      RETURN FALSE;
    end if;
  end LOOP;

  if SMR_ASN_SQL.DO_SHIPSKU_INSERTS(O_error_message) = FALSE then
    RETURN FALSE;
  end if;

  /*OLR V1.00 Removed for this interface
  if SMR_ASN_SQL.CREATE_INVOICE(O_error_message,
                            L_shipment,
                            I_asn.supplier,
                            L_ship_match) = FALSE then
     RETURN FALSE;
  end if;
  */
  ---
  IF NOT SHIPMENT_ATTRIB_SQL.CHECK_SHIPSKU(O_error_message,
                                           L_exists,
                                           L_shipment) then
    RETURN FALSE;
  END IF;

  IF NOT L_exists THEN
    O_error_message := SQL_LIB.CREATE_MSG('NO_SHIPSKU_RECORDS',
                                          L_shipment,
                                          NULL,
                                          NULL);
    RETURN FALSE;
  END IF;

  RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          to_char(SQLCODE));
    RETURN FALSE;
END PROCESS_ASN;

--------------------------------------------------------------------------------
-- Procedure Name: F_LOAD_ASNS
-- Purpose: [Fill in purpose]
--------------------------------------------------------------------------------
FUNCTION F_LOAD_ASNS(O_error_message IN OUT VARCHAR2) RETURN boolean IS
  L_program VARCHAR2(61) := package_name || '.F_LOAD_ASNS';

  L_temp_asn varchar2(30);

 CURSOR C_VALID_ASN IS
   SELECT DISTINCT case when oh.location in (9401,9402) then I.carton
                        when oh.location is null then
                             case when ol.location in (9401,9402) then I.carton
                                  else null
                             end
                        else null
                    end carton,
                    A.partner,
                    A.asn asn,
                    to_number(A.ship_to) ship_to,
                    A.ship_date,
                    A.est_arr_date,
                    A.courier,
                    oh.ship_pay_method ship_pay_method,
                    --SMR want last 17 digits of BOL if BOL > 17. Note SMR may use a tracking number in the BOL field and it may be > 17 characters.
                    case when nvl(length(A.bol_no),0) > 17 then
                         substr(A.bol_no , length(A.bol_no) - 16)
                         else A.bol_no
                    end as BOL_no,
                    A.vendor,
                    'C' carton_ind --For SMR all 856 will have a carton for every item.
      FROM smr_856_vendor_asn A,
           smr_856_vendor_order O,
           smr_856_vendor_item_2 I,
           ordhead oh,
           ordloc ol
     WHERE A.asn = O.asn
       and O.asn = I.asn
       and A.partner = O.partner
       and A.partner = I.partner
       and A.vendor = O.vendor
       and oh.order_no = O.order_no
       and O.order_no = I.order_no
       and O.order_loc = I.order_loc
       and oh.order_no = ol.order_no
       -- and ol.location in (9401,9402,9011) -- 1.03
       and ( ol.location in (9401,9402) or
             ol.location in (select wh
                               from v_smr_stand_alone_wh
                              where physical_wh_ind = 'N'))
     ORDER BY 2, 3, 1;

    CURSOR c_valid_order(I_asn VARCHAR2,
                         I_supplier NUMBER,
                         I_carton VARCHAR2,
                         I_partner number
                         ) is
    SELECT DISTINCT O.order_no, oh.not_after_date, to_number(O.order_loc) order_loc
      FROM smr_856_vendor_order O,
           smr_856_vendor_item_2 I,
           ordhead oh
     WHERE O.partner = I.partner
       and O.partner = I_partner
       and O.order_no = I.order_no
       and O.order_loc = I.order_loc
       and O.order_no = oh.order_no
       AND O.asn = I_asn
       AND O.vendor = I_supplier
       AND I.carton = nvl(I_carton,I.carton);

  CURSOR c_valid_carton(I_asn       VARCHAR2,
                        I_order_no  NUMBER,
                        I_order_loc NUMBER,
                        I_carton    varchar2) is
    SELECT DISTINCT carton, to_number(order_loc) order_loc
      FROM smr_856_vendor_item_2 I
     WHERE asn = I_asn
       AND order_no = I_order_no
       and order_loc = I_order_loc
       and carton = nvl(I_carton,carton)
     ORDER BY carton;

  CURSOR c_valid_item(I_asn VARCHAR2,
                      I_order_no NUMBER,
                      I_carton VARCHAR2,
                      I_order_loc number) IS
    SELECT to_char(sku_char)    sku_char,
           to_char(upc_char)    upc_char,
           to_number(order_loc) order_loc,
           SUM(units_shipped)   units_shipped
      FROM smr_856_vendor_item_2
     WHERE asn = I_asn
       AND order_no = I_order_no
       AND carton = I_carton
       AND order_loc = I_order_loc
     GROUP BY sku_char, UPC_char, order_loc;

   cursor c_asn_is_carton(I_asn_destination number) is
   select 'Y'
     from dual
    where I_asn_destination in (952,953,954)
       or exists (select 'x' from store where store = I_asn_destination);

   L_asn_is_carton varchar2(1);

BEGIN

  sho(L_program);

  --Capture valid ASNs for stores in process of closing...
  INSERT INTO smr_856_vendor_ari
  SELECT DISTINCT get_vdate,
         'N',
         'Ship Date for for ASN '||A.asn||
                      ', Order '||O.order_no||
                      ', store '||O.order_loc||
                          ' is '|| A.ship_date ||
            '. Last order date is'||to_char(st.store_close_date - nvl(STOP_ORDER_DAYS,0),'DD-MON-YYYY'),
         O.order_no,
         2
    FROM smr_856_vendor_asn A,
         smr_856_vendor_order O,
         store st
   WHERE A.partner = O.partner
     and A.asn = O.asn
     and a.vendor = O.vendor
     and O.order_loc = st.store
     and st.store_close_date IS NOT NULL
     and A.ship_date > (st.store_close_date - nvl(STOP_ORDER_DAYS,0))
   ORDER BY 3;

  --Capture valid ASNs for orders in worksheet...
  INSERT INTO smr_856_vendor_ari
  SELECT distinct GET_VDATE,
         'N',
         'Order is in worksheet status - '||O.order_no,
         O.order_no,
         1
    FROM smr_856_vendor_order O,
         ordhead oh
   WHERE O.order_no = oh.order_no
     and oh.status = 'W';

  FOR rec_asn IN C_VALID_ASN LOOP

    P_asn_record.carton          := rec_asn.carton;
    P_asn_record.asn             := rec_asn.asn;
    P_asn_record.destination     := rec_asn.ship_to;
    P_asn_record.ship_date       := rec_asn.ship_date;
    P_asn_record.est_arr_date    := rec_asn.est_arr_date;
    P_asn_record.carrier         := rec_asn.courier;
    P_asn_record.ship_pay_method := rec_asn.ship_pay_method;
    P_asn_record.inbound_bol     := rec_asn.bol_no;
    P_asn_record.supplier        := rec_asn.vendor;
    P_asn_record.carton_ind      := rec_asn.carton_ind;

    FOR rec_order in c_valid_order(P_asn_record.asn,
                                   P_asn_record.supplier,
                                   P_asn_record.carton,
                                   rec_asn.partner ) LOOP

      P_order_record.po_num := rec_order.ORDER_NO;

      FOR rec_carton IN c_valid_carton(P_asn_record.asn,
                                       P_order_record.po_num,
                                       rec_order.order_loc,
                                       P_asn_record.carton) LOOP

        open  c_asn_is_carton(P_asn_record.destination);
        fetch c_asn_is_carton into L_asn_is_carton;
        close c_asn_is_carton;

        if L_asn_is_carton = 'Y' then
           L_temp_asn := rec_carton.carton;
        else
           L_temp_asn := P_asn_record.asn;
        end if;

        IF PARSE_CARTON(O_error_message,
                        P_carton_table,
                        rec_carton.carton,
                        rec_order.order_loc,
                        L_temp_asn,
                        P_order_record.po_num) = false then

          RETURN FALSE;

        END IF;

        FOR rec_item IN c_valid_item(P_asn_record.asn,
                                     P_order_record.po_num,
                                     rec_carton.carton,
                                     rec_order.order_loc) loop

          IF PARSE_ITEM(O_error_message,
                        P_item_table,
                        rec_item.sku_char,
                        rec_item.units_shipped,
                        rec_item.UPC_char,
                        null, -- model/vpn
                        rec_item.order_loc,
                        L_temp_asn,
                        P_order_record.po_num,
                        rec_carton.carton) = false then

            RETURN FALSE;

          END IF;

        END LOOP;

      END LOOP;

      IF PROCESS_ASN(O_error_message,
                     P_asn_record,
                     P_order_record,
                     P_carton_table,
                     P_item_table,
                     'asnincre',
                     rec_order.order_loc) = false then
         RETURN FALSE;
      end if;

      P_item_table.delete;
      P_carton_table.delete;
      P_order_record := null;

    END LOOP;

    P_asn_record := null;

  END LOOP;

  INSERT INTO smr_856_vendor_successful (partner, asn, vendor, carton, pack_sku, sku, qty_shipped)
  SELECT distinct
         I.partner,
         I.asn,
         I.vendor,
         I.carton,
         decode(pb.pack_no, null, null, I.sku_char),
         decode(pb.pack_no, null, null, pb.item),
         decode(pb.pack_no, null, 0,    pb.pack_item_qty)
    FROM smr_856_vendor_item_2 I,
         packitem_breakout pb
   WHERE I.sku_char = pb.pack_no (+);

   /*For soft error with error Code 99 in the asn error file
     then there must be a record for that shipment
     in the asn no error file*/
   INSERT INTO SMR_856_VENDOR_SUCCESSFUL (partner, asn, vendor, carton, pack_sku, sku, qty_shipped)
   SELECT distinct
          partner,
          asn,
          vendor,
          '',
          '',
          '',
          nvl('','0')
     FROM SMR_856_VENDOR_ERRORS
    WHERE error_code = 99
          and error_type = 'S'
          and Upper(ERROR_VALUE) like 'DUPLICATE CARTON #%'
          and (partner, asn) not in (select distinct partner, asn from SMR_856_VENDOR_SUCCESSFUL);
          
          INSERT INTO SMR_856_VENDOR_SUCCESSFUL (partner, asn, vendor, carton, pack_sku, sku, qty_shipped)
   SELECT distinct
          partner,
          asn,
          vendor,
          '',
          '',
          '',
          nvl('','0')
     FROM SMR_856_VENDOR_ERRORS
    WHERE error_code = 77;

  RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_LOAD_ASNS;
-----------------------------------------------------------------------------------
--PUBLIC FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Procedure Name: F_PREPROCESS_TABLES
-- Purpose: Used to popualte values in tables so we don't have to join all the
--          time.
--------------------------------------------------------------------------------
FUNCTION F_PREPROCESS_TABLES(O_error_message IN OUT VARCHAR2) RETURN boolean IS

  L_program VARCHAR2(61) := package_name || '.F_PREPROCESS_TABLES';

BEGIN

  sho(L_program);

  update smr_856_vendor_asn I
     set vendor = (select O.vendor
                     from smr_856_vendor_order O
                    where O.asn = I.asn
                      AND O.partner = I.partner
                      and rownum < 2);

  update smr_856_vendor_item I
     set vendor = (select A.vendor
                     from smr_856_vendor_asn A
                    where A.asn = I.asn
                      AND A.partner = I.partner
                      and rownum < 2);

  --FIX ITEM AS ITEM IN FILE IS A NUMBER.

  --Good items
  INSERT INTO smr_856_vendor_item_2
  SELECT /*+ parallel (im,8) */
         I.partner,
         I.asn,
         I.order_no,
         I.order_loc,
         I.carton,
         I.upc upc,
         I.sku,
         im2.item,
         im.item,
         I.units_shipped,
         I.vendor
    FROM smr_856_vendor_item I,
         smr_item_master_856 im,
         smr_item_master_856 im2
   WHERE i.sku IS NOT NULL
     AND I.sku = im.num_item (+)
     and I.upc = im2.num_item (+);

  sho('INSERT smr_856_vendor_item_2 1:'||sql%rowcount);

  DBMS_STATS.GATHER_TABLE_STATS(OWNNAME => 'RMS13', TABNAME => 'SMR_856_VENDOR_ITEM_2',
                                METHOD_OPT => 'FOR ALL COLUMNS SIZE AUTO', BLOCK_SAMPLE => true, GRANULARITY => 'ALL',
                                cascade => true, NO_INVALIDATE => false, degree => 4);

  RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_PREPROCESS_TABLES;

--------------------------------------------------------------------------------
-- Procedure Name: F_CHECK_FILE_FAILED
-- Purpose: Any errors that would cause entire file to fail goes here.
--------------------------------------------------------------------------------
FUNCTION F_CHECK_FILE_FAILED(O_error_message IN OUT VARCHAR2,
                             O_file_failed   IN OUT BOOLEAN,
                             I_input_file    IN VARCHAR2) RETURN boolean IS

  L_program     VARCHAR2(61) := package_name || '.F_CHECK_FILE_FAILED';
  L_file_errors number;

BEGIN

  sho(L_program);

  O_file_failed := false;

  --ASN OR PARTNER IS NULL in any of the files.
  INSERT INTO smr_856_vendor_errors
  SELECT DISTINCT partner,
                  NULL ASN,
                  NULL Vendor,
                  99 error_code,
                  'H' error_type,
                  error_value,
                  P_fail_date,
                  'ALL' file_type
    FROM (SELECT partner, 'ASNSHIP_' || I_input_file || '.dat Null ASN' error_value
            FROM smr_856_vendor_asn
           WHERE asn IS NULL OR partner IS NULL
           UNION
          SELECT partner, 'ASNORDER_' || I_input_file || '.dat Null ASN' error_value
            FROM smr_856_vendor_order
           WHERE asn IS NULL OR partner IS NULL
           UNION
          SELECT partner, 'ASNITEM_' || I_input_file || '.dat Null ASN' error_value
            FROM smr_856_vendor_item
           WHERE asn IS NULL OR partner IS NULL);

  L_file_errors := sql%rowcount;
  IF L_file_errors != 0 then
    sho('NULL ASN:' || L_file_errors);
    O_file_failed := true;
    IF F_DELETE_ERRORED_RECORDS(O_error_message) = false then
      RETURN FALSE;
    END IF;
  END IF;

  --Same ASN/Partner does not appear in all 3 files.
  INSERT INTO smr_856_vendor_errors
  SELECT DISTINCT partner,
                  asn,
                  NULL Vendor,
                  99 error_code,
                  'H' error_type,
                  error_value error_value,
                  P_fail_date,
                  'ALL' file_type
    FROM (SELECT partner, asn,
                 'ASNSHIP_' || I_input_file || '.dat Missing ASN/Partner' error_value
            FROM (SELECT distinct partner, asn
                    FROM smr_856_vendor_order
                  MINUS
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_asn
                  UNION
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_item
                  MINUS
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_asn)
          union
          SELECT partner, asn,
                 'ASNSORDER_' || I_input_file || '.dat Missing ASN/Partner' error_value
            FROM (SELECT distinct partner, asn
                    FROM smr_856_vendor_asn
                  MINUS
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_order
                  UNION
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_item
                  MINUS
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_order)
          union
          SELECT partner,
                 asn,
                 'ASNITEM_' || I_input_file || '.dat Missing ASN/Partner' error_value
            FROM (SELECT distinct partner, asn
                    FROM smr_856_vendor_asn
                  MINUS
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_item
                  UNION
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_order
                  minus
                  SELECT distinct partner, asn
                    FROM smr_856_vendor_item));

  L_file_errors := sql%rowcount;
  IF L_file_errors != 0 then
    sho('Missing ASN:' || L_file_errors);
    O_file_failed := true;
    IF F_DELETE_ERRORED_RECORDS(O_error_message) = false then
      RETURN FALSE;
    END IF;
  END IF;

  RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_CHECK_FILE_FAILED;

--------------------------------------------------------------------------------
-- Procedure Name: F_VALIDATE_FILES
-- Purpose: [Fill in purpose]
--------------------------------------------------------------------------------
FUNCTION F_VALIDATE_FILES(O_error_message IN OUT VARCHAR2,
                          O_file_errors   IN OUT NUMBER,
                          O_file_failed   IN OUT BOOLEAN,
                          I_input_file    IN VARCHAR2) RETURN BOOLEAN IS

  L_program VARCHAR2(61) := package_name || '.F_VALIDATE_FILES';

  -----------------------------------------
  --Non fatal errors - these would cause the ASN to be rejected, not the whole file.
  -----------------------------------------
  L_file_error   number(10, 0);
  L_total_errors number(10, 0);
  --

BEGIN

  sho(L_program);

  --Check fatal errros
  IF F_CHECK_FILE_FAILED(O_error_message, O_file_failed, I_input_file) =
     false then
    RETURN FALSE;
  ELSE
    --If any fatal errors, return AND allow calling function to handle cleanup.
    --We do this so that the next set of files will be processed if they exist.
    IF O_file_failed THEN
      sho('File failed bad records:' || O_file_errors);
      RETURN TRUE;
    END IF;

  END IF;

  --check non fatal errors.
  L_file_error   := 0;
  L_total_errors := 0;

  IF F_PREPROCESS_TABLES(O_error_message) = false then
    RETURN FALSE;
  END IF;

  ------------------------------------------------------------------------------------------------------------------------
  --VALIDATE ASN
  ------------------------------------------------------------------------------------------------------------------------
  --Same ASN/PARTNER appears more than once in the ASNSHIP file.
  INSERT INTO smr_856_vendor_errors
  SELECT partner,
         ASN,
         NULL ,
         99 error_code,
         'H' error_type,
         'ASN/SUPP duplicate in ASN_' || I_input_file || '.dat' error_value,
         P_fail_date,
         'ASN' file_type
    FROM smr_856_vendor_asn
   group by partner, ASN
  having count(*) > 1;

  L_file_error := sql%rowcount;
  sho('Duplicate ASN/Partner:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --ii.12 = Invalid Location Number
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor vendor,
                    12 error_code,
                    'H' error_type,
                    substr(ship_to,1,50) error_value,
                    P_fail_date,
                    'ASN' file_type
      FROM smr_856_vendor_asn A
     WHERE (ship_to is null or is_number(ship_to) is null)
        OR (    NOT EXISTS (SELECT 'x' FROM wh WHERE wh = A.ship_to)
            --AND NOT EXISTS (SELECT 'x' FROM store WHERE STORE = A.ship_to and nvl(store_close_date,ship_date+1) > ship_date)); OLR V1.04 Removed
            AND NOT EXISTS (SELECT 'x' FROM store WHERE STORE = A.ship_to)); -- OLR V1.04 Inserted

  L_file_error := sql%rowcount;
  sho('Invalid ship to 1:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  /* --OLR V1.02 Delete START
  --viii. 71 = Store/wh not on PO but on ASN
  INSERT INTO smr_856_vendor_errors
    SELECT distinct A.partner,
                    A.asn,
                    O.vendor,
                    71 error_code,
                    'H' error_type,
                    A.ship_to error_value,
                    P_fail_date,
                    'ASN' file_type
      FROM smr_856_vendor_asn A,
           (SELECT DISTINCT partner, asn, order_no, vendor
              FROM smr_856_vendor_order) O,
           ordhead oh,
           ordloc  ol
     WHERE A.asn = O.asn
       and A.vendor = O.vendor
       and A.partner = O.partner
       and A.vendor = oh.supplier
       AND O.order_no = oh.order_no
       AND O.order_no = ol.order_no
       AND ol.location in (9401,9402,9011)
       AND oh.status in ('A', 'W', 'S', 'C')
       AND (   (ship_to is null or is_number(ship_to) is null)
            OR (nvl(oh.location, ol.location) = 9402 and to_number(a.ship_to) not in (select store from store))
            OR (nvl(oh.location, ol.location) = 9401 and to_number(a.ship_to) not in (952,953,954))
            OR (nvl(oh.location, ol.location) = 9011 and to_number(a.ship_to) != 901 ));

  L_file_error := sql%rowcount;
  sho('Invalid ship to 2:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;
  --OLR V1.02 Delete END */

  --77 = "Ship to location not on PO".
  INSERT INTO smr_856_vendor_errors
    SELECT distinct A.partner,
                    A.asn,
                    A.vendor,
                    77 error_code,
                    'H' error_type,
                    substr(A.ship_to,1,50) error_value,
                    P_fail_date,
                    'ASN' file_type
      FROM smr_856_vendor_asn A,
           (SELECT DISTINCT partner, asn, order_no, vendor
              FROM smr_856_vendor_order) O,
           ordhead oh,
           ordloc  ol
     WHERE A.asn = O.asn
       and A.vendor = O.vendor
       and A.vendor = oh.supplier
       and A.partner = O.partner
       AND O.order_no = oh.order_no
       AND O.order_no = ol.order_no
       -- AND ol.location in (9401,9402,9011) -- 1.03
       and ( ol.location in (9401,9402) or
             ol.location in (select wh
                               from v_smr_stand_alone_wh
                              where physical_wh_ind = 'N'))
       AND (   (A.ship_to IS NULL or is_number(A.ship_to) is null)
            OR (
                ( nvl(oh.location, ol.location) = 9401 and A.ship_to not in (952,953,954))
                  OR
                ( nvl(oh.location, ol.location) = 9402 and A.ship_to not in (select store from store))
                  OR
                ( nvl(oh.location, ol.location) not in (9401,9402) and A.ship_to != (SELECT PHYSICAL_WH FROM WH WHERE WH = nvl(oh.location, ol.location)))
               )
           );

  L_file_error := sql%rowcount;
  sho('Invalid ship to 3:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --ii.99 = Invalid ship date
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT A.partner,
                    A.asn,
                    A.vendor vendor,
                    99 error_code,
                    'H' error_type,
                    'Ship date is missing.' error_value,
                    P_fail_date,
                    'ASN' file_type
      FROM smr_856_vendor_asn A
     WHERE A.ship_date IS NULL;

  L_file_error := sql%rowcount;
  sho('Invalid ship date:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  /*
  --99 = Invalid estimated arrival date
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT asn,
                    vendor vendor,
                    99 error_code,
                    'H' error_type,
                    'Invalid est_arr_date - ' ||
                    to_char(est_arr_date, 'DD-MON-YYYY') error_value,
                    P_fail_date,
                    'ASN' file_type
      FROM smr_856_vendor_asn A
     WHERE est_arr_date IS NOT NULL
       AND (est_arr_date < (SELECT max(oh.not_before_date)
                              FROM smr_856_vendor_order O, ordhead oh
                             WHERE oh.order_no = O.order_no
                               AND O.asn = A.asn) OR
            est_arr_date > (SELECT min(oh.not_after_date)
                               FROM smr_856_vendor_order O, ordhead oh
                              WHERE oh.order_no = O.order_no
                                AND O.asn = A.asn));

  L_file_error := sql%rowcount;
  sho('Invalid est arrival date:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;
  */

  --ii.79 = Invalid BOL Number
 /* INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor vendor,
                    79 error_code,
                    'S' error_type,
                    'Invalid BOL ' ||bol_no error_value,
                    P_fail_date,
                    'ASN' file_type
      FROM smr_856_vendor_asn A
     WHERE length(nvl(bol_no,1)) > 17;

  L_file_error := sql%rowcount;
  sho('Invalid BOL:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error; */

  ------------------------------------------------------------------------------------------------------------------------
  --VALIDATE ORDER
  ------------------------------------------------------------------------------------------------------------------------
  --Same ASN/ORDER appears more than once in the ASNORDER file.
  INSERT INTO smr_856_vendor_errors
  SELECT partner,
         ASN ASN,
         NULL Vendor,
         99 error_code,
         'H' error_type,
         'ASN/ORDER appears twice in ASN_' || I_input_file ||
         '.dat' error_value,
         P_fail_date,
         'ORDER' file_type
    FROM smr_856_vendor_order
   GROUP BY partner, asn, order_no, order_loc
  having count(*) > 1;

  L_file_error := sql%rowcount;
  sho('Duplicate ASN/ORDER:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --i. 10 = Invalid PO
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor,
                    10 error_code,
                    'H' error_type,
                    order_no ||lpad(order_loc,3,'0') error_value,
                    P_fail_date,
                    'ORDER' file_type
      FROM smr_856_vendor_order O
     WHERE NOT EXISTS (SELECT 'x'
                         FROM ordhead oh
                        WHERE oh.status IN ('A', 'W', 'S', 'C')
                          AND oh.order_no = O.order_no);

  L_file_error := sql%rowcount;
  sho('Invalid order number:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --ii.12 = Invalid Location Number
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor,
                    12 error_code,
                    'H' error_type,
                    substr(mark_for,1,50) error_value,
                    P_fail_date,
                    'ORDER' file_type
      FROM smr_856_vendor_order O
     WHERE    (mark_for is null or is_number(mark_for) is null)
           or (    NOT EXISTS (SELECT 'x' FROM wh WHERE wh = nvl(O.mark_for,-1))
               --AND NOT EXISTS (SELECT 'x' FROM store WHERE STORE = nvl(O.mark_for,-1) and nvl(store_close_date,get_vdate+1) > get_vdate)); OLR V1.04 Removed
               AND NOT EXISTS (SELECT 'x' FROM store WHERE STORE = nvl(O.mark_for,-1))); -- OLR V1.04 Inserted

  L_file_error := sql%rowcount;
  sho('Invalid order mark for:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor,
                    99 error_code,
                    'H' error_type,
                    'Invalid location ' || order_loc error_value,
                    P_fail_date,
                    'ITEM' file_type
      FROM smr_856_vendor_order O
     WHERE NOT EXISTS (SELECT 'x' FROM wh WHERE wh = nvl(O.order_loc,-1))
       --AND NOT EXISTS (SELECT 'x' FROM store WHERE STORE = nvl(O.order_loc,-1) and nvl(store_close_date,get_vdate+1) > get_vdate); OLR V1.04 Removed
       AND NOT EXISTS (SELECT 'x' FROM store WHERE STORE = nvl(O.order_loc,-1)); -- OLR V1.04 Inserted

  L_file_error := sql%rowcount;
  sho('Invalid order order loc:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --vii.  62 = PO Not Assigned to Vendor on ASN
  INSERT INTO smr_856_vendor_errors
  SELECT distinct O.partner,
                  O.asn,
                  O.vendor,
                  62 error_code,
                  'H' error_type,
                  O.order_no||lpad(order_loc,3,'0') || '/' || O.vendor error_value,
                  P_fail_date,
                  'ORDER' file_type
    FROM smr_856_vendor_order O, ordhead oh
   WHERE oh.order_no = O.order_no
     AND oh.supplier != nvl(O.vendor, -1);

  L_file_error := sql%rowcount;
  sho('Invalid vendor :' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --viii. 71 = Store/wh not on PO but on ASN
  /*  INSERT INTO smr_856_vendor_errors
          SELECT distinct O.partner,
                    O.asn,
                    O.vendor,
                    71 error_code,
                    'H' error_type,
                    substr(O.mark_for,1,50) error_value,
                    P_fail_date,
                    'ORDER' file_type
      FROM smr_856_vendor_order  O,
           smr_856_vendor_item_2 I,
           ordhead oh,
           ordloc  ol
     WHERE O.asn = I.asn
       and O.vendor = I.vendor
       and O.partner = I.partner
       and O.order_no = I.order_no
       and O.order_loc = I.Order_loc
       and O.order_no = oh.order_no
       AND oh.status in ('A', 'W', 'S', 'C')
       AND O.order_no = ol.order_no
       -- AND ol.location in (9401,9402,9011) -- 1.03
       and ( ol.location in (9401,9402) or
             ol.location in (select wh
                               from v_smr_stand_alone_wh
                              where physical_wh_ind = 'N'))
       AND (   (O.mark_for is null OR is_number(O.mark_for) is null)
            OR (nvl(oh.location, ol.location) in (9402,9401) and to_number(O.mark_for) not in (select store from store))
            -- OR (nvl(oh.location, ol.location) = 9011 and to_number(O.mark_for) != 901 )); -- 1.03
            OR (nvl(oh.location, ol.location) not in (9402,9401) and to_number(O.mark_for) != (SELECT PHYSICAL_WH FROM WH WHERE WH = nvl(oh.location, ol.location))));

  L_file_error := sql%rowcount;
  sho('Invalid ship to 2:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error; */

  ------------------------------------------------------------------------------------------------------------------------
  --VALIDATE ITEM
  ------------------------------------------------------------------------------------------------------------------------
  --i. 10 = Invalid PO
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor,
                    10 error_code,
                    'H' error_type,
                    order_no||lpad(order_loc,3,'0') error_value,
                    P_fail_date,
                    'ITEM' file_type
      FROM smr_856_vendor_item_2 I
     WHERE NOT EXISTS (SELECT 'x'
                         FROM ordhead oh
                        WHERE oh.status IN ('A', 'W', 'S', 'C')
                          AND oh.order_no = I.order_no);

  L_file_error := sql%rowcount;
  sho('Invalid item order:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --iii.  29 = Invalid SKU/UPC Combination
  --Bad records
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT I.partner,
                    I.asn,
                    I.vendor,
                    29 error_code,
                    'H' error_type,
                    I.sku || '/' || I.upc error_value,
                    P_fail_date,
                    'ITEM' file_type
      FROM smr_856_vendor_item_2 I
     WHERE I.upc is not null
       and not exists (select 'x'
                         from item_master
                        where item_parent = I.sku_char
                          and item = I.upc_char);

  L_file_error := sql%rowcount;
  sho('Invalid item/upc combination:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --If SKU is invalid for order, but valid for supplier, then put in ARI table
  INSERT INTO smr_856_vendor_ari
   SELECT get_vdate,
           'N',
           'Item '||I.sku_char||' is invalid for order '||I.order_no||' but is valid for supplier '||I.vendor,
           I.order_no,
           3
      FROM smr_856_vendor_item_2 I
     WHERE I.sku_char IS NOT NULL
       AND NOT EXISTS (SELECT 'x'
                         FROM ordsku os,
                              (select pb.pack_no, pb.item
                                 from packitem_breakout pb,
                                      item_master im
                                where pb.pack_no = im.item
                                  and im.pack_type = 'B') buyer_pack
                        WHERE os.order_no = I.order_no
                          AND os.item = buyer_pack.pack_no (+)
                          AND I.sku_char = nvl(buyer_pack.item,os.item))
       AND EXISTS (SELECT 'x'
                     FROM item_supplier isp,
                          (select pb.pack_no, pb.item
                             from packitem_breakout pb,
                                  item_master im
                            where pb.pack_no = im.item
                              and im.pack_type = 'B') buyer_pack
                    WHERE I.vendor = isp.supplier
                      and isp.item = buyer_pack.pack_no (+)
                      and I.sku_char = nvl(buyer_pack.item,isp.item));

  --iv.   49 = SKU not on order
/*  INSERT INTO smr_856_vendor_errors
  SELECT / parallel (oh,8) 
           I.partner,
           I.asn,
           I.vendor,
           49 error_code,
           'H' error_type,
           I.sku||'/'||I.order_no||LPAD(order_loc,3,'0') error_value,
           P_fail_date,
           'ITEM' file_type
      FROM smr_856_vendor_item_2 I,
           ordhead
     WHERE ordhead.order_no = I.order_no
       AND NOT EXISTS (SELECT 'x'
                         FROM ordloc ol,
                              (SELECT pb.pack_no, pb.item
                                 FROM packitem_breakout pb,
                                      item_master im
                                WHERE pb.pack_no = im.item
                                  AND im.pack_type = 'B') buyer_pack
                        WHERE ol.order_no = I.order_no
                          AND ol.item = buyer_pack.pack_no (+)
                          AND NVL(I.sku_char,'x') = nvl(buyer_pack.item,ol.item)
                          AND ol.location not in (9521,9531,9541));

  L_file_error := sql%rowcount;
  sho('Invalid sku on order :' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;
*/
  --v.    50 = SKU/UPC/EAN not valid in RMS
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT I.partner,
                    I.asn,
                    I.vendor,
                    50 error_code,
                    'H' error_type,
                    I.sku||'/'||I.order_no||lpad(order_loc,3,'0') error_value,
                    P_fail_date,
                    'ITEM' file_type
      FROM smr_856_vendor_item_2 I
     WHERE (NVL(I.sku,0) != 0 AND I.sku_char is null);

  L_file_error := sql%rowcount;
  sho('Invalid sku or upc:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  -- 99 = Invalid item order loc
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor,
                    99 error_code,
                    'H' error_type,
                    'Invalid order location ' || order_loc error_value,
                    P_fail_date,
                    'ITEM' file_type
      FROM smr_856_vendor_item_2 I
     WHERE NOT exists (SELECT 'x' FROM wh WHERE wh = nvl(I.order_loc,-1))
       AND NOT exists (SELECT 'x' FROM store WHERE store = nvl(I.order_loc,-1));

  L_file_error := sql%rowcount;
  sho('Invalid item order location:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  -- 78 = Invalid item carton
/*  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor,
                    78 error_code,
                    'H' error_type,
                    rpad(nvl(carton,' '),50,' '),
                    P_fail_date,
                    'ITEM' file_type
      FROM smr_856_vendor_item_2
     WHERE length(nvl(carton,' ')) != 20;

  L_file_error := sql%rowcount;
  sho('Invalid carton:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error; */

  -- 99 = Invalid item units_shipped
  INSERT INTO smr_856_vendor_errors
    SELECT DISTINCT partner,
                    asn,
                    vendor,
                    99 error_code,
                    'H' error_type,
                    'Invalid units for order/item ' || order_no || '/' ||
                    sku error_value,
                    P_fail_date,
                    'ITEM' file_type
      FROM smr_856_vendor_item_2
     WHERE nvl(units_shipped, 0) <= 0;

  L_file_error := sql%rowcount;
  sho('Invalid units shipped:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  INSERT INTO smr_856_vendor_errors
  select distinct partner,
         asn,
         vendor,
         99 error_code,
         'H',
         'Carton twice in same file ' ||carton error_value,
         P_fail_date,
         'ASN' file_type
    from SMR_856_VENDOR_ITEM_2
   where carton in (SELECT carton
                      FROM SMR_856_VENDOR_ITEM_2 A
                     group by carton
                    having count(distinct A.order_no||A.order_loc||A.partner) > 1);

  L_file_error := sql%rowcount;
  sho('Carton twice in same file:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  INSERT INTO smr_856_vendor_errors
  select distinct partner,
         asn,
         vendor,
         99 error_code,
         'S',
         'Duplicate carton #' ||carton error_value,
         P_fail_date,
         'ASN' file_type
    from SMR_856_VENDOR_ITEM_2
   where exists (SELECT 'x'
                   FROM shipsku
                  where carton = SMR_856_VENDOR_ITEM_2.carton);

  L_file_error := sql%rowcount;
  sho('Duplicate carton:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error;

  --9402 order where item does not have associated allocation
 /* INSERT INTO smr_856_vendor_errors
  select distinct I2.partner,
         I2.asn,
         I2.vendor,
         80 error_code,
         'H',
         I2.order_no||'/'||I2.sku_char error_value,
         P_fail_date,
         'ASN' file_type
    from SMR_856_VENDOR_ITEM_2 I2,
         ordhead oh
   where oh.order_no = I2.order_no
     and nvl(oh.location,-1) = 9402
     and not exists (select 'x'
                       from alloc_header ah,
                            (select pb.pack_no, pb.item
                                 from packitem_breakout pb,
                                      item_master im
                                where pb.pack_no = im.item
                                  and im.pack_type = 'B') buyer_pack
                      where ah.order_no = I2.order_no
                        and ah.item = buyer_pack.pack_no (+)
                        and nvl(buyer_pack.item,ah.item) = I2.sku_char);

  L_file_error := sql%rowcount;
  sho('9402 with no allocation:' || L_file_error);
  L_total_errors := L_total_errors + L_file_error; */

  O_file_errors := L_total_errors;

  RETURN TRUE;
EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_VALIDATE_FILES;

--------------------------------------------------------------------------------
-- Procedure Name: F_PROCESS_FILES
-- Purpose: Main function
--------------------------------------------------------------------------------
FUNCTION F_PROCESS_FILES(O_error_message IN OUT VARCHAR2,
                         O_file_errors   IN OUT NUMBER,
                         O_file_failed   IN OUT BOOLEAN,
                         I_input_file    IN VARCHAR2,
                         I_now           IN DATE) RETURN boolean IS

  L_program VARCHAR2(61) := package_name || '.F_PROCESS_FILES';

BEGIN

  sho(L_program);

  --Set package level variables
  P_fail_date := I_now;

  --clean out temp table
  execute immediate 'delete from smr_856_vendor_item_2';

  IF F_VALIDATE_FILES(O_error_message,
                      O_file_errors,
                      O_file_failed,
                      I_input_file) = false then
    RETURN FALSE;
  ELSE

     --If file fails - return true so that calling program will move on to next file if available.
     IF O_file_failed then
       RETURN TRUE;

     --File errors are rejected records that do not stop the file from being processed.
     ELSIF NVL(O_file_errors, 0) > 0 THEN

       sho('O_file_errors=' || O_file_errors);

       IF F_DELETE_ERRORED_RECORDS(O_error_message) = false then
         RETURN FALSE;
       END IF;

     END IF;

     IF F_LOAD_ASNS(O_error_message) = false then
       RETURN FALSE;
     END IF;

 END IF;

  sho('DONE');

  RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_PROCESS_FILES;

----------------------------------------------------------------------------------------------------------------------------------------------------------------

END;
/
