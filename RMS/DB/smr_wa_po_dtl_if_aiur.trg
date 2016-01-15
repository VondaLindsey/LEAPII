Create or replace TRIGGER smr_wa_po_dtl_if_aiur_trg
 AFTER INSERT OR UPDATE ON smr_po_edi_850_860_dtl_exp 
  FOR EACH ROW

DECLARE

   L_order_no      ordhead.order_no%TYPE;
   L_location      ordhead.location%TYPE;
   L_item          item_master.item%TYPE;   
   L_pack_cnt      number(10) := 0; /* vendor pack */
   L_ordcnt        number(10) := 0; 

BEGIN

   if ( :new.REC_TYPE1 = 'S850D3' ) then /* get details (860 next) */ 
   
     L_item := :new.ITEM_SKU_NMBR;
     L_order_no := :new.PO_NMBR;
     
     select count(*)
       into L_pack_cnt
       from item_master 
      where item = L_item
        and pack_ind = 'Y'
        and pack_type = 'V';
     
    if ( INSERTING ) then

     if (:new.STORE is not null ) then /* standalone */

/**
       select count(*) into L_ordcnt
         from ordhead  where order_no = L_order_no;

       if ( L_ordcnt = 0 ) then
         L_order_no := substr(L_order_no,1,6);
       end if;     
**/
       insert into SMR_RMS_WH_PO_DTL_STG (
         order_no,
         physical_wh,
         location,
         item,
         pack_ind,
         qty_ordered ) values (
         L_order_no,
         substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
         :new.STORE,
         :new.ITEM_SKU_NMBR,
         decode(L_pack_cnt,1,'Y','N'),
         :new.STORE_QUANTITY);         
     else /* SDQ */       
       if (:new.SDQ1_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ1_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ1_STORE_QUANTITY);
       end if;
     end if;      
    elsif ( UPDATING ) then
       if (:new.SDQ8_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ8_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ8_STORE_QUANTITY);
       elsif (:new.SDQ7_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ7_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ7_STORE_QUANTITY);
       elsif (:new.SDQ6_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ6_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ6_STORE_QUANTITY);
       elsif (:new.SDQ5_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ5_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ5_STORE_QUANTITY);
       elsif (:new.SDQ4_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ4_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ4_STORE_QUANTITY);
       elsif (:new.SDQ3_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ3_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ3_STORE_QUANTITY);
       elsif (:new.SDQ2_STORE is not null) then
         insert into SMR_RMS_WH_PO_DTL_STG (
           order_no,
           physical_wh,
           location,
           item,
           pack_ind,
           qty_ordered ) values (
           L_order_no,
           substr(:new.DC_STORE_NMBR,1,3),  /* w.physical_wh */
           :new.SDQ2_STORE,
           :new.ITEM_SKU_NMBR,
           decode(L_pack_cnt,1,'Y','N'),
           :new.SDQ2_STORE_QUANTITY);
       end if;
     end if;
     
     /* remove po details not in header */
     delete from SMR_RMS_WH_PO_DTL_STG
      where order_no in (
            select order_no from SMR_RMS_WH_PO_DTL_STG where order_no = L_order_no
             minus
            select order_no from SMR_RMS_WH_PO_HDR_EXP where order_no = L_order_no);

     update SMR_RMS_WH_PO_DTL_STG
        set group_id = (select max(group_id) from SMR_RMS_WH_PO_HDR_EXP where order_no = L_order_no)
      where order_no = L_order_no;
   end if;


EXCEPTION
   WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: smr_wa_po_if_aiur_trg - '||
                                     ' Order_no '||L_order_no||
                                     ' - '||SQLERRM);

end;
/

