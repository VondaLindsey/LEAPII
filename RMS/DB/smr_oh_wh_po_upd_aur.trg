Create or replace TRIGGER smr_oh_wh_po_upd_aur_trg
 AFTER update of status ON ordhead
  FOR EACH ROW

DECLARE

   L_order_no             ordhead.order_no%TYPE;
   L_item                 item_master.item%TYPE;
   L_group_id             smr_rms_wh_po_hdr_exp.group_id%TYPE;
   L_interface_id         smr_rms_int_queue.interface_id%TYPE;
   L_record_id            smr_rms_wh_po_hdr_exp.record_id%TYPE;
   L_sa_po_cnt            number(10) := 0;
   L_int_queue_N_cnt      number(10) := 0;
   L_smr_split_po_len     number(10) := SMR_LEAP_INTERFACE_SQL.SPLIT_PO_ORDER_LENGTH;
   
   L_full_order_no        ordhead.order_no%TYPE;
   L_ProcessingCode       varchar2(6) := 'UPDATE';
   L_status               varchar2(6) := 'Active';
   L_po_type              varchar2(6) := 'BULK';
   L_pack_ind             varchar2(1) :=  null;

   O_error_message        rtk_errors.rtk_text%type := null;

   GEN_GROUP_ID           exception; 
   
   cursor rollup_dtl_cur is
     select item,
            sum(nvl(qty_ordered,0)) qty_ordered
       from ordloc 
      where order_no = L_order_no
      group by item
   order by 1;
   
BEGIN
  
   L_order_no := :new.order_no;

   select count(*)
     into L_sa_po_cnt
     from ordloc
    where order_no = L_order_no 
      and length(order_no) < L_smr_split_po_len
      and location in (select wh from wh_attributes where wh_type_code = 'PA');
    
   if ( L_sa_po_cnt > 0 ) then /* SA wh PO */
          
     select interface_id
       into L_interface_id
       from smr_rms_int_type
      where interface_name = 'WH_PO';

     if ( SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID(O_error_message,
                                                 L_interface_Id,
                                                 L_group_id) = FALSE ) then
       raise GEN_GROUP_ID;
     end if;        
     
     L_record_id := 1;
     L_full_order_no := L_order_no||substr(:new.location,2,3);
     insert into SMR_RMS_WH_PO_HDR_UPD_STG(
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
       modifyDate) values (
       L_group_id,
       L_record_id,
       L_ProcessingCode,
       L_full_order_no,
       :new.location,                      /* oh.location   */
       :new.location,  
       substr(:new.location,1,3),          /* w.physical_wh */
       L_po_type,
       :new.order_type,
       L_status,
       :new.freight_terms,
       :new.supplier,
       :new.buyer,
       :new.dept,
       :new.earliest_ship_date,
       :new.latest_ship_date,
       :new.not_before_date,
       :new.not_after_date, 
       sysdate);

       L_record_id := 1;
       for rollup_dtl_rec in rollup_dtl_cur loop
       
         L_item := rollup_dtl_rec.item;

         select decode(pack_type,'V','Y','N')
           into L_pack_ind
           from item_master
          where item = L_item;

         insert into SMR_RMS_WH_PO_DTL_UPD_STG (
           group_id,     
           record_id,    
           order_no,     
           physical_wh,  
           item,         
           pack_ind,     
           qty_ordered  ) values (
           L_group_id,
           L_record_id,
           L_full_order_no,
           substr(:new.location,1,3),    /* w.physical_wh */
           L_item,
           L_pack_ind,
           rollup_dtl_rec.qty_ordered);         
           
         L_record_id := L_record_id + 1;
       end loop;
    end if;

EXCEPTION
   WHEN GEN_GROUP_ID THEN
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: smr_oh_wh_po_upd_aur_trg - GEN_GROUP_ID - '||
                                     ' Order_no '||to_char(L_order_no)||' '||O_error_message);
   WHEN OTHERS       THEN
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: smr_oh_wh_po_upd_aur_trg - '||
                                     ' Order_no '||to_char(L_order_no)||' '||' - '||SQLERRM);
end;
/
