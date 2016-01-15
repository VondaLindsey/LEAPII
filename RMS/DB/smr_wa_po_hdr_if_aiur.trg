Create or replace TRIGGER smr_wa_po_hdr_if_aiur_trg
 AFTER INSERT OR UPDATE ON smr_po_edi_850_860_hdr_exp
  FOR EACH ROW

DECLARE

   L_order_no             ordhead.order_no%TYPE;
   L_status               varchar2(6);
   L_ProcessingCode       varchar2(6);
   L_po_type              varchar2(5);
   L_location             ordhead.location%TYPE;
   L_order_type           ordhead.order_type%TYPE;
   L_freight_terms        ordhead.freight_terms%TYPE;
   L_earliest_ship_date   ordhead.earliest_ship_date%TYPE;
   L_latest_ship_date     ordhead.latest_ship_date%TYPE;
   L_ordstore             store.store%TYPE;
   L_ordstcnt             number(10) := 0;
   L_ordcnt               number(10) := 0;

   L_PO_SHIP_DATE         varchar2(8):= :new.PO_SHIP_DATE;
   L_PO_CANCEL_DATE       varchar2(8):= :new.PO_CANCEL_DATE;
   
   O_error_message rtk_errors.rtk_text%type := null;
   L_group_id      smr_rms_wh_po_hdr_exp.group_id%TYPE;
   L_interface_id  smr_rms_int_queue.interface_id%TYPE;
   L_record_id     smr_rms_wh_po_hdr_exp.record_id%TYPE;
   
   GEN_GROUP_ID    exception;
   
   CURSOR ordhead_cur IS
   SELECT location,
          order_type,
          freight_terms,
          earliest_ship_date,
          latest_ship_date
     FROM ordhead
    WHERE order_no = L_order_no;

   CURSOR ordstore_cur IS
   SELECT count(*) cnt
     FROM store
    WHERE store = L_ordstore;    
    
BEGIN

   if (( substr(:new.REC_TYPE1,5,2) = 'H1' )  and   /* new PO */ 
               (:new.PO_TYPE       != 'BK' )) then  /* allocated or stand-alone orders only */ 
 
    if  ( :new.PO_TYPE = 'RL' ) then
      L_ordstore := to_number(substr(:new.PO_NMBR,7));
      OPEN  ordstore_cur;
      FETCH ordstore_cur 
       INTO L_ordstcnt;
      CLOSE ordstore_cur;
    end if;

   
    if ( L_ordstcnt = 0 ) then /* not a DD order - send to WA */

     L_ordcnt := 0;
     L_order_no := :new.PO_NMBR;
     select count(*) into L_ordcnt
       from ordhead  where order_no = L_order_no;



     if ( L_ordcnt = 0 ) then
       L_order_no := to_number(substr(to_char(L_order_no),1,6));
     end if;     
     

     OPEN  ordhead_cur;
     FETCH ordhead_cur 
      INTO L_location,
           L_order_type,
           L_freight_terms,
           L_earliest_ship_date,
           L_latest_ship_date;
     CLOSE ordhead_cur;

     if ( substr(:new.REC_TYPE1,2,3) = '850') then
       L_ProcessingCode := 'INSERT';
     else
       L_ProcessingCode := 'UPDATE';
     end if;
     
     L_status := 'Active';
   
     if ( :new.PO_TYPE = 'RL' ) then 
       L_po_type := 'XDCK';
     else
       L_po_type := 'BULK';
     end if;

     select interface_id
       into L_interface_id
       from smr_rms_int_type
      where interface_name = 'WH_PO';

     if ( SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID(O_error_message,
                                                 L_interface_Id,
                                                 L_group_id) = FALSE ) then
       raise GEN_GROUP_ID;
     end if;        
   
     begin
       select nvl(max(record_id) + 1, 1)
         into L_record_id
         from SMR_RMS_WH_PO_HDR_EXP 
        where order_no = L_order_no;
     exception
       when NO_DATA_FOUND then
         L_record_id := 1;
     end;

     insert into SMR_RMS_WH_PO_HDR_EXP(
       group_id,
       record_id,
       ProcessingCode,
       order_no,
       location,
       wh,
       physical_wh,
       po_type,
       order_type,
       Status,
       freight_terms,
       supplier,
       Buyer,
       dept,
       earliest_ship_date,
       latest_ship_date,
       not_before_date,
       not_after_date,
       modifyDate ) values (
       L_group_id,
       L_record_id,
       L_ProcessingCode,
       :new.PO_NMBR,
       L_location,                      /* oh.location   */
       L_location,  
/*       substr(:new.DC_STORE_NMBR,1,3),/* w.physical_wh */
       substr(L_location,1,3),          /* w.physical_wh */
       L_po_type,
       L_order_type,
       L_status,
       L_freight_terms,
       :new.SUPPLIER_NMBR,
       :new.BUYER_NMBR,
       :new.DEPT_NMBR,
       L_earliest_ship_date,
       L_latest_ship_date,
       to_date(decode(L_PO_SHIP_DATE,  '00000000',null,L_PO_SHIP_DATE),  'YYYYMMDD'), /* newNotBeforeDate */
       to_date(decode(L_PO_CANCEL_DATE,'00000000',null,L_PO_CANCEL_DATE),'YYYYMMDD'), /* newNotAfterDate  */
       :new.CREATE_DATETIME );

    end if;
  end if;

EXCEPTION
   WHEN GEN_GROUP_ID THEN
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: smr_wa_po_if_aiur_trg - GEN_GROUP_ID - '||
                                     ' Order_no '||to_char(L_order_no)||' '||O_error_message);
   WHEN OTHERS       THEN
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: smr_wa_po_if_aiur_trg - '||
                                     ' Order_no '||to_char(L_order_no)||' '||to_char(L_ordstore)||' '||
                                     ' - '||SQLERRM);

end;
/
