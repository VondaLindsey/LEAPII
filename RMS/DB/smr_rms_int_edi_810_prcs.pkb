CREATE OR REPLACE PACKAGE BODY RMS13.SMR_RMS_INT_EDI_810 AS

-- Program Global Variables
p_create_datetime date ;
P_total_thead     number(10) := 0;
P_total_tdetl     number(10) := 0;
P_total_recs      number(10) := 0;
P_total_prcs_recs number(10) := 0;

  TYPE error_rec IS RECORD (
      group_id              SMR_RMS_INT_ERROR.GROUP_ID%TYPE,
      record_id             SMR_RMS_INT_ERROR.RECORD_ID%TYPE,
      error_msg             SMR_RMS_INT_ERROR.ERROR_MSG%TYPE,
      hdr_dtl_ind           CHAR(1),
      vendor                SMR_IM_EDI_REJECT.VENDOR%TYPE, 
      ext_doc_id            SMR_IM_EDI_REJECT.EXT_DOC_ID%TYPE,
      error_code            SMR_IM_EDI_REJECT.ERROR_CODE%TYPE,
      batch_id              SMR_IM_EDI_REJECT.BATCH_ID%TYPE,
      sku                   SMR_IM_EDI_REJECT.SKU%TYPE,
      upc                   SMR_IM_EDI_REJECT.UPC%TYPE, 
      total_cost            SMR_IM_EDI_REJECT.TOTAL_COST%TYPE,
      total_qty             SMR_IM_EDI_REJECT.TOTAL_QTY%TYPE );
    
    TYPE int_error_tab is TABLE OF error_rec;
    t_error_rec           int_error_tab := int_error_tab();
    
    
      TYPE process_rec IS RECORD (
          group_id              SMR_RMS_INT_ERROR.GROUP_ID%TYPE,
          record_id             SMR_RMS_INT_ERROR.RECORD_ID%TYPE,
          hdr_dtl_ind           CHAR(1),
          vendor                SMR_IM_EDI_REJECT.VENDOR%TYPE );
     
     TYPE int_process_tab is TABLE OF process_rec;
          t_process_rec           int_process_tab := int_process_tab();

    
      TYPE data_rec IS RECORD (
          supplier              sups.supplier%type,
          formatted_data        VARCHAR2(4000),
          create_datetime       DATE,
          hdr_dtl_ind           CHAR(1),
          row_num               number(10)
        );
        
        TYPE int_data_tab is TABLE OF data_rec;
        t_data_rec           int_data_tab := int_data_tab();
        t_data_rec_stg       int_data_tab := int_data_tab();
        
        p_formatted_rec     VARCHAR2(4000);

------------------------------------------------------------------------------------
FUNCTION LOAD_STAGING(O_error_message          IN OUT VARCHAR2 )
return boolean  IS
  ---
  L_program VARCHAR2(64) := 'SMR_RMS_INT_EDI_810.LOAD_STAGING';


BEGIN

   FORALL i in 1 .. t_data_rec.count
      insert into SMR_EDI_810_FINAL_FILE_FORMAT 
          values ( t_data_rec(i).supplier,
                   t_data_rec(i).formatted_data,
                   t_data_rec(i).hdr_dtl_ind,
                   p_create_datetime,
                   t_data_rec(i).row_num );
   
 
  return TRUE;
EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          NULL);
    return FALSE;
END LOAD_STAGING;

------------------------------------------------------------------------------------
FUNCTION CREATE_ERROR(O_error_message          IN OUT VARCHAR2 )
return boolean  IS
  ---
  L_program VARCHAR2(64) := 'SMR_RMS_INT_EDI_810.CREATE_ERROR';
  L_interface_error_id    VARCHAR2(50);
   PRAGMA AUTONOMOUS_TRANSACTION;

    cursor c_INTERFACE_ERROR_ID is
          select interface_id|| '_'||INTERFACE_NAME || '_' ||to_char(get_vdate, 'YYYYMMDD') || '_'  
               from SMR_RMS_INT_TYPE
       where interface_name = 'EDI_810';
BEGIN

    open c_INTERFACE_ERROR_ID;
   fetch c_INTERFACE_ERROR_ID into L_interface_error_id;
   close c_INTERFACE_ERROR_ID;
      
       FORALL i in 1 .. t_error_rec.count            
        insert into SMR_RMS_INT_ERROR ( INTERFACE_ERROR_ID,
                                        GROUP_ID,
                                        RECORD_ID,
                                        ERROR_MSG,
                                        CREATE_DATETIME)
                               values ( L_interface_error_id || lpad(SMR_RMS_INT_EDI_810_SEQ.nextval, 10, 0) ,
                                        t_error_rec(i).group_id,
                                        t_error_rec(i).record_id,
                                        t_error_rec(i).error_msg,
                                        p_create_datetime);
                                          
       FORALL i in 1 .. t_error_rec.count      
         insert into SMR_IM_EDI_REJECT ( VENDOR, 
                                         EXT_DOC_ID, 
                                         BATCH_ID, 
                                         ERROR_CODE, 
                                         SKU, 
                                         UPC, 
                                         UPLD_TIMESTAMP, 
                                         TOTAL_COST, 
                                         TOTAL_QTY)
                                 values (t_error_rec(i).vendor,
                                         t_error_rec(i).ext_doc_id,
                                         null,
                                         t_error_rec(i).error_code,
                                         t_error_rec(i).sku,
                                         t_error_rec(i).upc,
                                         p_create_datetime,
                                         t_error_rec(i).total_cost,
                                         t_error_rec(i).total_qty);
 commit;
 
  return TRUE;
EXCEPTION
  when OTHERS then
  rollback;
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          NULL);
    return FALSE;
END CREATE_ERROR;
------------------------------------------------------------------------------------
FUNCTION UPDATE_PRCS(O_error_message          IN OUT VARCHAR2)
return boolean  IS
  ---
  L_program VARCHAR2(64) := 'SMR_RMS_INT_EDI_810.UPDATE_PRCS';

BEGIN


  FORALL i in 1 .. t_error_rec.count                                         
     update SMR_RMS_INT_EDI_810_DTL_IMP
        set processed = 'Y',
            error_ind = 'E',
            processed_date = p_create_datetime
      where group_id = t_error_rec(i).group_id
        and record_id = case when t_error_rec(i).hdr_dtl_ind = 'D' then
                          t_error_rec(i).record_id
                       else
                           record_id
                       end;

 FORALL i in 1 .. t_error_rec.count
    update SMR_RMS_INT_EDI_810_HDR_IMP
       set processed = 'Y',
           error_ind = 'E',
           processed_date = p_create_datetime
     where group_id = t_error_rec(i).group_id
       and record_id = case when t_error_rec(i).hdr_dtl_ind = 'H' then
                        t_error_rec(i).record_id
                   else
                        record_id
                       end;

  FORALL i in 1 .. t_process_rec.count                                         
     update SMR_RMS_INT_EDI_810_DTL_IMP
        set processed = 'Y',
            processed_date = p_create_datetime
      where group_id = t_process_rec(i).group_id
        and record_id = case when t_process_rec(i).hdr_dtl_ind = 'D' then
                          t_process_rec(i).record_id
                       else
                           record_id
                       end;
       
  FORALL i in 1 .. t_process_rec.count
    update SMR_RMS_INT_EDI_810_HDR_IMP
       set processed = 'Y',
           processed_date = p_create_datetime
     where group_id = t_process_rec(i).group_id
       and record_id = case when t_process_rec(i).hdr_dtl_ind = 'H' then
                        t_process_rec(i).record_id
                   else
                        record_id
                       end;   
                       
  return TRUE;
EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          NULL);
    return FALSE;
END UPDATE_PRCS;
------------------------------------------------------------------------------------

FUNCTION VALIDATE_DATA(O_error_message          IN OUT VARCHAR2,
                       I_num_threads            IN     NUMBER,
                       I_thread_val             IN     NUMBER )
return boolean IS
  ---
L_program VARCHAR2(64) := 'SMR_RMS_INT_EDI_810.VALIDATE_DATA';
L_order_no           ordhead.order_no%type;
L_terms              terms.terms%type;
L_invoice_number     varchar2(50);
L_invoice_date       date;
L_ship_date          date;
L_vendor_po          sups.supplier%type;
L_supplier           sups.supplier%type;
L_tot_inv_ext_cost   Number(20,4);
L_total_cost         Number(20,4);
L_detail_total_cost  Number(20,4);
L_loc                store.store%type;
L_item               item_master.item%type;
L_upc                item_master.item%type;
L_due_date           date;
L_dummy              varchar2(50);
L_group_id           SMR_RMS_INT_EDI_810_HDR_IMP.group_id%type;
L_err_ind            number(2) := 0;
    

cursor c_drv_supp is 
   select distinct driver_value supplier
      from v_restart_supplier
     where driver_name = 'SUPPLIER'
       and num_threads = I_num_threads
       and thread_val  = I_thread_val
       and driver_value in (select distinct vendor_id 
                     from SMR_RMS_INT_EDI_810_HDR_IMP
                     where processed = 'N' );


cursor c_hdr is
select GROUP_ID, 
       RECORD_ID,
       DOCUMENT_TYPE, 
       VENDOR_DOCUMENT_NUMBER, 
       VENDOR_TYPE, 
       VENDOR_ID, 
       VENDOR_DOCUMENT_DATE, 
       ORDER_NUMBER, 
       LOCATION, 
       LOCATION_TYPE, 
       TERMS, 
       DUE_DATE, 
       PAYMENT_METHOD, 
       CURRENCY_CODE, 
       EXCHANGE_RATE, 
       TOTAL_COST, 
       SIGN_INDICATOR_COST, 
       TOTAL_VAT_AMOUNT, 
       SIGN_INDICATOR_VAT, 
       TOTAL_QUANTITY, 
       SIGN_INDICATOR_QTY, 
       TOTAL_DISCOUNT, 
       SIGN_INDICATOR_DISC,
       FREIGHT_TYPE, 
       nvl(PAID_IND, 'N') PAID_IND, 
       nvl(MULTI_LOCATION, 'N') multi_location, 
       nvl(CONSIGNMENT_INDICATOR, 'N') consignment_indicator, 
       DEAL_ID, 
       DEAL_APPROVAL_INDICATOR, 
       NVL(RTV_INDICATOR, 'N') RTV_INDICATOR, 
       CUSTOM_DOCUMENT_REFERENCE_1, 
       CUSTOM_DOCUMENT_REFERENCE_2, 
       CUSTOM_DOCUMENT_REFERENCE_3, 
       CUSTOM_DOCUMENT_REFERENCE_4, 
       CROSS_REF_DOCUMENT_NUMBER
  from SMR_RMS_INT_EDI_810_HDR_IMP
 where processed = 'N'
   and vendor_id = L_supplier;

  cursor c_dtl is
   select GROUP_ID, 
          UPC, 
          UPC_SUPPLEMENT, 
          ITEM, 
          VPN, 
          SIGN_INDICATOR_QTY, 
          ORIGINAL_DOCUMENT_QUANTITY, 
          SIGN_INDICATOR_COST, 
          ORIGINAL_UNIT_COST, 
          ORIGINAL_VAT_CODE, 
          ORIGINAL_VAT_RATE, 
          SIGN_INDICATOR_VAT, 
          TOTAL_ALLOWANCE, 
          PROCESSED 
     from SMR_RMS_INT_EDI_810_DTL_IMP
  where processed = 'N'
    and group_id = L_group_id;

    cursor c_chk_order is
        select supplier 
          from ordhead 
         where order_no = L_order_no;
         
    cursor c_chk_item is
       select 1
         from item_master
        where item = L_item;
        
    cursor c_chk_terms is
       select 1
         from terms
        where terms = L_terms;
        
    cursor c_chk_loc is
      select 1 
        from store
       where store = L_loc
       union
      select 1
        from wh
       where wh = L_loc;
     
    cursor c_true_dup is
      select 'x' 
        from im_doc_head 
       where EXT_DOC_ID = L_invoice_number  
         and ORDER_NO = L_order_no  
         and status != 'DELETE'  
         and ( supplier_site_id = L_vendor_po  
              or vendor = L_vendor_po ) 
          and TOTAL_COST = L_total_cost  ; 
       
BEGIN
           P_total_prcs_recs := 0;
    for r_sup in c_drv_supp loop
            P_total_recs     := 0;
           P_total_prcs_recs := P_total_prcs_recs + 1;
           P_total_recs := P_total_recs + 1;
           p_create_datetime   := sysdate;
           
            L_supplier := r_sup.supplier;
            p_formatted_rec := 'FHEAD'|| LPAD(P_total_recs, 10,0)||'UPINV'||to_char(p_create_datetime, 'YYYYMMDDHH24MISS' ); 
            t_data_rec_stg.delete;
             
            t_data_rec_stg.extend;
            t_data_rec_stg(t_data_rec_stg.last).supplier := L_supplier;
            t_data_rec_stg(t_data_rec_stg.last).formatted_data := p_formatted_rec;
            t_data_rec_stg(t_data_rec_stg.last).create_datetime :=  p_create_datetime;
            t_data_rec_stg(t_data_rec_stg.last).hdr_dtl_ind :=  'F';     
            t_data_rec_stg(t_data_rec_stg.last).row_num     :=   P_total_prcs_recs;
            P_total_thead    := 0;
            P_total_tdetl    := 0;
           

          for r1 in c_hdr loop
         -- First Validate each record if it can be rejected or accepted.
         -- Rejected means (Hard Edit) in old lingo, basically reim will reject these records
         -- when order_no is null, invoice_number null etc
         -- All others we will produce a file which will be loaded into ReIM either succesfully (IM_DOC_HEAD)
         -- or unsuccesfully (IM_EDI_REJECT_DOC_HEAD)

         -- Invalid PO Number    10    BIG04    HARD    H2    Either order number is null or alpha numeric or does not exist in ordhead.
         -- Invalid Terms Code    11    ITD01    HARD    N/A    Terms does not exist in terms in RMS.
         -- Invoice No. Blank    12    BIG02    HARD    H1    Invoice number Blank or no leading zeros or not in the format specified in reim.properties
         -- Invoice Date Invalid    13    BIG01    HARD    H1    Vendor document date is blank or not a date
         -- Ship Date Invalid    14    DTM02    HARD    H1    
         -- EDI Vendor Diff in PO File    15    REF02    HARD    H2    Vendor is not the same as supplier on Order.
         -- Tot Inv. Not Equal to Extended Items    16    TDS01    HARD    H2    Total Cost on header not equal to detail sum within tolerance. 
         -- Tot Inv. Amt Equal to Zero    17    TDS01    HARD    H1    Total Cost zero or alpha numeric
         -- Invalid Store Number    18    N104    HARD    H2    Location is not a store or wh.
         -- Invalid SKU    19    IT107    HARD    H2    Item does not exist in item_master
         -- Invalid UPC    20    IT109    HARD    H2    Item is not a UPC.
         -- True Duplicate     85    **    HARD    H2    (85-Not sent to Vendor-EDISYS ONLY) Same vendor, same order, same total cost, same vendor document is considered True duplicate ["Duplicate Invoice – DO NOT RESEND"]-Liaison
         -- Invalid Due Date      88    **    HARD    H1    Due date > 90 days from invoice date
 
            L_order_no           := r1.order_number;
            L_terms              := r1.terms;
            L_invoice_number     := r1.VENDOR_DOCUMENT_NUMBER;
            L_invoice_date       := to_date(r1.VENDOR_DOCUMENT_DATE, 'YYYYMMDDHH24MISS');
            L_vendor_po          := r1.vendor_id;
          --  L_tot_inv_ext_cost   Number(20,4);
            L_total_cost         := r1.total_cost;
            L_loc                := r1.LOCATION;
         --   L_item               := r1.item;
         --   L_upc                := r1.upc;
            L_due_date           := to_date(r1.due_date, 'YYYYMMDDHH24MISS');  
            L_group_id           := r1.group_id;
         --   L_rec_ind            := 0;
            L_err_ind            := 0;
            open c_chk_order;
           fetch c_chk_order into L_dummy;
            close c_chk_order;

           if L_dummy is null then
               t_error_rec.extend;
               t_error_rec(t_error_rec.last).group_id := L_group_id;
               t_error_rec(t_error_rec.last).record_id := r1.record_id;
               t_error_rec(t_error_rec.last).error_msg := ' Order No ' || L_order_no || ' does not exist in RMS';
               t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
               t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
               t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
               t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
               t_error_rec(t_error_rec.last).error_code   := 10;
               t_error_rec(t_error_rec.last).sku          := null;
               t_error_rec(t_error_rec.last).upc          := null;
               t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
               t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;
               L_err_ind := 1;
            end if;
            if L_dummy <> L_vendor_po then
               t_error_rec.extend;
               t_error_rec(t_error_rec.last).group_id := L_group_id;
               t_error_rec(t_error_rec.last).record_id := r1.record_id;
               t_error_rec(t_error_rec.last).error_msg := 'Order No ' || L_order_no || ' vendor ' || L_dummy || ' is different from vendor ' || r1.vendor_id || '  provided on invoice';
               t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
               t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
               t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
               t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
               t_error_rec(t_error_rec.last).error_code   := '15';
               t_error_rec(t_error_rec.last).sku          := null;
               t_error_rec(t_error_rec.last).upc          := null;
               t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
               t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;
               L_err_ind := 1;
            end if;
        
            open c_chk_terms;
           fetch c_chk_terms into L_dummy;
            close c_chk_terms;
            if L_terms is not null and L_dummy is null then
               t_error_rec.extend;
               t_error_rec(t_error_rec.last).group_id := L_group_id;
               t_error_rec(t_error_rec.last).record_id := r1.record_id;
               t_error_rec(t_error_rec.last).error_msg := 'Terms ' || L_terms || ' is invalid and does not exist in RMS ';
               t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
               t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
               t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
               t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
               t_error_rec(t_error_rec.last).error_code   := 11;
                t_error_rec(t_error_rec.last).sku          := null;
               t_error_rec(t_error_rec.last).upc          := null;
               t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
               t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
               L_err_ind := 1;
            end if;
            if L_invoice_number is null or substr(L_invoice_number,1,1) = '0' then
               t_error_rec.extend;
               t_error_rec(t_error_rec.last).group_id := L_group_id;
               t_error_rec(t_error_rec.last).record_id := r1.record_id;
               t_error_rec(t_error_rec.last).error_msg := 'Invoice Number ' || L_invoice_number || ' is invalid or in incorrect format ';
               t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
               t_error_rec(t_error_rec.last).vendor := r1.vendor_id;   
               t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
               t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
               t_error_rec(t_error_rec.last).error_code   := 12;
               t_error_rec(t_error_rec.last).sku          := null;
               t_error_rec(t_error_rec.last).upc          := null;
               t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
               t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
               L_err_ind := 1;
            end if;
            if L_invoice_date is null then
               t_error_rec.extend;
               t_error_rec(t_error_rec.last).group_id := L_group_id;
               t_error_rec(t_error_rec.last).record_id := r1.record_id;
               t_error_rec(t_error_rec.last).error_msg := 'Invoice Date ' || L_invoice_date || ' is null ';
               t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
               t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
               t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
               t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
               t_error_rec(t_error_rec.last).error_code   := 13;
               t_error_rec(t_error_rec.last).sku          := null;
               t_error_rec(t_error_rec.last).upc          := null;
               t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
               t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
               L_err_ind := 1;
            end if;

            open c_chk_loc;
           fetch c_chk_loc into L_dummy;
            close c_chk_loc;

            if L_dummy is null then
               t_error_rec.extend;
               t_error_rec(t_error_rec.last).group_id := L_group_id;
               t_error_rec(t_error_rec.last).record_id := r1.record_id;
               t_error_rec(t_error_rec.last).error_msg := 'Location ' || L_loc || ' is invalid Location ';
               t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
               t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
               t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
               t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
               t_error_rec(t_error_rec.last).error_code   := 18;
               t_error_rec(t_error_rec.last).sku          := null;
               t_error_rec(t_error_rec.last).upc          := null;
               t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
               t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
               L_err_ind := 1;
            end if;
                   -- Check True Duplicate
             open c_true_dup;
            fetch c_true_dup into L_dummy;
             close c_true_dup;

             if L_dummy is null then
                t_error_rec.extend;
                t_error_rec(t_error_rec.last).group_id := L_group_id;
                t_error_rec(t_error_rec.last).record_id := r1.record_id;
                t_error_rec(t_error_rec.last).error_msg := ' True Duplicate Invoice  ' || L_invoice_number || ' Order no ' || L_order_no || ' Supplier ' || L_vendor_po || ' Total Cost ' || L_total_cost;
                t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
                    t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
                    t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
                    t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
                    t_error_rec(t_error_rec.last).error_code   := 85;
                    t_error_rec(t_error_rec.last).sku          := null;
                    t_error_rec(t_error_rec.last).upc          := null;
                    t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
                    t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
                L_err_ind := 1;
              end if;
              if L_total_cost = 0 then
                 t_error_rec.extend;
                 t_error_rec(t_error_rec.last).group_id := L_group_id;
                 t_error_rec(t_error_rec.last).record_id := r1.record_id;
                 t_error_rec(t_error_rec.last).error_msg := ' Invoice  ' || L_invoice_number || ' Order no ' || L_order_no || '  Invalid Total Cost ' || L_total_cost;
                 t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
                 t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
                 t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
                 t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
                 t_error_rec(t_error_rec.last).error_code   := 17;
                 t_error_rec(t_error_rec.last).sku          := null;
                 t_error_rec(t_error_rec.last).upc          := null;
                 t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
                 t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
                 L_err_ind := 1;              
              end if;
         --- Loop through the details for each invoice check item, upc and total cost
         -- check total cost between header and detail if it is within Tolerance

         if L_err_ind = 0 then
             P_total_thead   := P_total_thead + 1;
             P_total_recs    := P_total_recs + 1;
             P_total_prcs_recs := P_total_prcs_recs + 1;
             
             p_formatted_rec := 'THEAD'|| LPAD(P_total_recs, 10,0)||LPAD(P_total_thead, 10,0) 
                 || rpad( nvl(r1.document_type, ' '), 6,' ')  || rpad( nvl(r1.vendor_document_number, ' '), 30,' ')
                 || rpad( nvl(null, ' '), 10,' ') || rpad( nvl(r1.vendor_type, ' '), 6,' ')
                 || LPAD(to_number(r1.vendor_id), 10,0)|| to_char(L_invoice_date, 'YYYYMMDDHH24MISS') 
                 || LPAD(r1.order_number, 10,0)  || LPAD(r1.location, 10,0)|| r1.location_type
                 || rpad ((case when r1.terms is null then  'D' else r1.terms end), 15, ' ')
                 || to_char(L_due_date, 'YYYYMMDDHH24MISS')|| rpad( nvl(r1.payment_method, ' '), 6,' ')
                 || rpad( nvl(r1.currency_code, ' '), 3,' ') || lpad( nvl(r1.EXCHANGE_RATE, 0) * 10000, 12,0)  
                 || r1.SIGN_INDICATOR_COST || lpad( nvl(r1.TOTAL_COST, 0) * 10000, 20,0)
                 || r1.SIGN_INDICATOR_VAT || lpad( nvl(r1.TOTAL_VAT_AMOUNT, 0) * 10000, 20,0)
                 || r1.SIGN_INDICATOR_QTY || lpad( nvl(r1.TOTAL_QUANTITY, 0) * 10000, 12,0)
                 || r1.SIGN_INDICATOR_DISC || lpad( nvl(r1.TOTAL_DISCOUNT, 0) * 10000, 12,0) 
                 || rpad( nvl(r1.FREIGHT_TYPE, ' '), 6,' ')|| rpad( nvl(r1.PAID_IND, ' '), 1,' ')|| rpad( nvl(r1.MULTI_LOCATION, ' '), 1,' ')
                 || rpad( nvl(r1.CONSIGNMENT_INDICATOR, ' '), 1,' ')|| rpad( nvl(to_char(r1.DEAL_ID), ' '), 10,' ') || rpad( nvl(r1.DEAL_APPROVAL_INDICATOR, ' '), 1,' ')
                 || rpad( nvl(r1.RTV_INDICATOR, ' '), 1,' ')  || rpad( nvl(r1.CUSTOM_DOCUMENT_REFERENCE_1, ' '), 90,' ')
                 || rpad( nvl(r1.CUSTOM_DOCUMENT_REFERENCE_2, ' '), 90,' ') || rpad( nvl(r1.CUSTOM_DOCUMENT_REFERENCE_3, ' '), 90,' ')
                 || rpad( nvl(r1.CUSTOM_DOCUMENT_REFERENCE_4, ' '), 90,' ') || rpad( nvl(to_char(r1.CROSS_REF_DOCUMENT_NUMBER), ' '), 10,' ') ; 
         
                 t_data_rec_stg.extend;
                 t_data_rec_stg(t_data_rec_stg.last).supplier := r1.vendor_id;
                 t_data_rec_stg(t_data_rec_stg.last).formatted_data := p_formatted_rec;
                 t_data_rec_stg(t_data_rec_stg.last).create_datetime :=  p_create_datetime;
                 t_data_rec_stg(t_data_rec_stg.last).hdr_dtl_ind :=  'H';  
                 t_data_rec_stg(t_data_rec_stg.last).row_num     :=   P_total_prcs_recs;
         end if;     
      ------################################ DETAIL PROCESSING START ########################   
           L_detail_total_cost := 0;
           P_total_tdetl       := 0;
           for r2 in c_dtl loop
            if r2.item is not null then
                 L_item := r2.item;
                 open c_chk_item ;
                 fetch c_chk_item into L_dummy;
                 close c_chk_item;
            end if;  
            if L_dummy is null and r2.item is not null then
               t_error_rec.extend;
               t_error_rec(t_error_rec.last).group_id := L_group_id;
               t_error_rec(t_error_rec.last).record_id := r1.record_id;
               t_error_rec(t_error_rec.last).error_msg := 'Item ' || L_item || ' does not exist in RMS ';
               t_error_rec(t_error_rec.last).hdr_dtl_ind := 'D';
               t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
               t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
               t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
               t_error_rec(t_error_rec.last).error_code   := 19;
               t_error_rec(t_error_rec.last).sku          := null;
               t_error_rec(t_error_rec.last).upc          := null;
               t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
               t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
               L_err_ind := 1;
            end if;
            if r2.upc is not null then
                 L_item := r2.upc;
              open c_chk_item ;
             fetch c_chk_item into L_dummy;
              close c_chk_item;
                end if;
             if L_dummy is null and r2.upc is not null then
                t_error_rec.extend;
                t_error_rec(t_error_rec.last).group_id := L_group_id;
                t_error_rec(t_error_rec.last).record_id := r1.record_id;
                t_error_rec(t_error_rec.last).error_msg := 'UPC ' || L_item || ' is not valid in RMS  ';
                t_error_rec(t_error_rec.last).hdr_dtl_ind := 'D';
                    t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
                    t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
                    t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
                    t_error_rec(t_error_rec.last).error_code   := 20;
                    t_error_rec(t_error_rec.last).sku          := null;
                    t_error_rec(t_error_rec.last).upc          := null;
                    t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
                    t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
                L_err_ind := 1;
            end if;
            L_detail_total_cost := L_detail_total_cost + ( r2.ORIGINAL_DOCUMENT_QUANTITY * r2.ORIGINAL_UNIT_COST);

            if L_err_ind = 0 then
                 P_total_recs    := P_total_recs + 1;
                 P_total_tdetl   := P_total_tdetl + 1;
                 P_total_prcs_recs := P_total_prcs_recs + 1;

                p_formatted_rec := 'TDETL'|| LPAD(P_total_recs, 10,0)||LPAD(P_total_thead, 10,0) || rpad( nvl(r2.upc, ' '), 25,' ')
                                 || rpad( nvl(to_char(r2.upc_supplement), ' '), 5,' ') || rpad( nvl(r2.item, ' '), 25,' ')
                                 || rpad( nvl(r2.vpn, ' '), 30,' ') || r2.sign_indicator_qty
                                 || lpad( nvl(r2.original_document_quantity, 0) * 10000, 12,0) 
                                 || r2.sign_indicator_cost || lpad( nvl(r2.original_unit_cost, 0) * 10000, 20,0)
                                 || rpad(nvl(r2.original_vat_code, ' '), 6, ' ' ) || lpad( nvl(r2.original_vat_rate, 0) * 10000, 20,0)
                                 || r2.sign_indicator_vat
                                 || lpad( nvl(r2.total_allowance, 0) * 10000, 20,0);
                           
                      t_data_rec_stg.extend;
                      t_data_rec_stg(t_data_rec_stg.last).supplier := L_vendor_po;
                      t_data_rec_stg(t_data_rec_stg.last).formatted_data := p_formatted_rec;
                      t_data_rec_stg(t_data_rec_stg.last).create_datetime :=  p_create_datetime;
                      t_data_rec_stg(t_data_rec_stg.last).hdr_dtl_ind :=  'D';   
                      t_data_rec_stg(t_data_rec_stg.last).row_num     :=   P_total_prcs_recs;
            end if;
            
           end loop; -- Loop through Details
        dbms_output.put_line( '555xxxxx');

          ------################################ DETAIL PROCESSING END ########################   
     

                if L_total_cost <> L_detail_total_cost then
                    t_error_rec.extend;
                    t_error_rec(t_error_rec.last).group_id := L_group_id;
                    t_error_rec(t_error_rec.last).record_id := r1.record_id;
                    t_error_rec(t_error_rec.last).error_msg := ' Invoice  ' || L_invoice_number || ' Order no ' || L_order_no || ' Header Total Cost ' || L_total_cost || ' not equal to Detail Total cost ' || L_detail_total_cost;
                    t_error_rec(t_error_rec.last).hdr_dtl_ind := 'H';
                    t_error_rec(t_error_rec.last).vendor := r1.vendor_id;      
                    t_error_rec(t_error_rec.last).ext_doc_id   := L_invoice_number;
                    t_error_rec(t_error_rec.last).batch_id     := r1.CUSTOM_DOCUMENT_REFERENCE_1;
                    t_error_rec(t_error_rec.last).error_code   := 16;
                    t_error_rec(t_error_rec.last).sku          := null;
                    t_error_rec(t_error_rec.last).upc          := null;
                    t_error_rec(t_error_rec.last).total_cost   := r1.total_cost;
                    t_error_rec(t_error_rec.last).total_qty    := r1.total_quantity;           
                    L_err_ind := 1;              
                end if;
                
                if L_err_ind = 0 then
                    P_total_recs    := P_total_recs + 1;
                    P_total_prcs_recs := P_total_prcs_recs + 1;
                    p_formatted_rec := 'TTAIL'|| LPAD(P_total_recs, 10, 0)||LPAD(P_total_thead, 10,0) || Lpad( P_total_tdetl, 6,0); 
                    t_data_rec_stg.extend;
                    t_data_rec_stg(t_data_rec_stg.last).supplier := L_vendor_po;
                    t_data_rec_stg(t_data_rec_stg.last).formatted_data := p_formatted_rec;
                    t_data_rec_stg(t_data_rec_stg.last).create_datetime :=  p_create_datetime;
                    t_data_rec_stg(t_data_rec_stg.last).hdr_dtl_ind :=  'T'; 
                    t_data_rec_stg(t_data_rec_stg.last).row_num     :=   P_total_prcs_recs; 
                end if;
         if L_err_ind = 1 then
            t_data_rec_stg.delete;
            continue;
         else
            t_process_rec.extend;
            t_process_rec(t_process_rec.last).group_id := L_group_id;
            t_process_rec(t_process_rec.last).record_id  := r1.record_id;
            t_process_rec(t_process_rec.last).hdr_dtl_ind := 'H';
            t_process_rec(t_process_rec.last).vendor      := r1.vendor_id;
         end if;

        --- No Errors in the data so now format the header and detail records and insert into Staging table
        --- each vendor will have one set of data in the staging table, so we can generate one file per supplier
        --- so reim ediupload can run in multi threading and performance will be better
             if P_total_tdetl > 0 then
                 for i in 1 .. t_data_rec_stg.count loop
                     t_data_rec.extend;
                     t_data_rec(t_data_rec.last).supplier := t_data_rec_stg(i).supplier;
                     t_data_rec(t_data_rec.last).formatted_data := t_data_rec_stg(i).formatted_data;
                     t_data_rec(t_data_rec.last).create_datetime :=  p_create_datetime;
                     t_data_rec(t_data_rec.last).hdr_dtl_ind :=  t_data_rec_stg(i).hdr_dtl_ind;  
                     t_data_rec(t_data_rec.last).row_num     :=  t_data_rec_stg(i).row_num;
                  end loop;
             end if;
             t_data_rec_stg.delete;
         --- 
        end loop; -- End of Header record
        if P_total_tdetl > 0 then
           P_total_recs    := P_total_recs + 1;
           P_total_prcs_recs := P_total_prcs_recs + 1;
           p_formatted_rec := 'FTAIL'||LPAD(P_total_recs, 10, 0)||LPAD(P_total_recs-2, 10,0); 
           t_data_rec.extend;
           t_data_rec(t_data_rec.last).supplier := r_sup.supplier;
           t_data_rec(t_data_rec.last).formatted_data := p_formatted_rec;
           t_data_rec(t_data_rec.last).create_datetime :=  p_create_datetime;
           t_data_rec(t_data_rec.last).hdr_dtl_ind :=  'X';      
           t_data_rec(t_data_rec.last).row_num  := P_total_prcs_recs;
        end if;
     end loop; -- end of supplier
             if CREATE_ERROR (O_error_message ) = FALSE then
                return FALSE;
             end if;

             if LOAD_STAGING (O_error_message ) = FALSE then
                return FALSE;
             end if;
              if UPDATE_PRCS (O_error_message ) = FALSE then
                return FALSE;
              end if;
     
     
  return TRUE;
EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          NULL);
    return FALSE;
END VALIDATE_DATA;
------------------------------------------------------------------------------------
FUNCTION EDI810_POST(O_error_message          IN OUT VARCHAR2 )
return boolean  IS
  ---
  L_program VARCHAR2(64) := 'SMR_RMS_INT_EDI_810.EDI810_POST';


BEGIN

-- move all processed records into Hisoty tables from SMR_RMS_INT_EDI_810_HDR_IMP to SMR_RMS_INT_EDI_810_HDR_HIST
-- SMR_RMS_INT_EDI_810_DTL_HIST
-- SMR_EDI_810_FINAL_FILE_HIST

insert into SMR_RMS_INT_EDI_810_HDR_HIST
select * from SMR_RMS_INT_EDI_810_HDR_IMP
 where processed = 'Y';

insert into SMR_RMS_INT_EDI_810_DTL_HIST
select * from SMR_RMS_INT_EDI_810_DTL_IMP
 where processed = 'Y';
 
 insert into SMR_EDI_810_FINAL_FILE_HIST
   select * from SMR_EDI_810_FINAL_FILE_FORMAT;
   
   delete from SMR_RMS_INT_EDI_810_DTL_IMP
    where processed = 'Y';  
    
      delete from SMR_RMS_INT_EDI_810_HDR_IMP
       where processed = 'Y';
       

      delete from SMR_EDI_810_FINAL_FILE_FORMAT; 
   
 commit;
  return TRUE;
EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          NULL);
    return FALSE;
END EDI810_POST;

------------------------------------------------------------------------------------
FUNCTION EDI810_PRE(O_error_message          IN OUT VARCHAR2 )
return boolean  IS
  ---
  L_program VARCHAR2(64) := 'SMR_RMS_INT_EDI_810.EDI810_PRE';
  
  L_start_line_id   varchar2(10);
  L_end_line_id     varchar2(10);
  L_record_id       number(10) := 0;
  L_interface_id    SMR_RMS_INT_TYPE.interface_id%type;
  L_guid            varchar2(50);
  guid_err   EXCEPTION;

  
   cursor c_hdr is
 SELECT LEAD (LINE_ID) OVER (ORDER BY LINE_ID) AS NEXT_line_id,
         hdr.RECORD_DESCRIPTOR,
         hdr.LINE_ID,
         hdr.TRANSACTION_NUMBER,
         hdr.DOCUMENT_TYPE,
         hdr.VENDOR_DOCUMENT_NUMBER,
         hdr.GROUP_ID,
         hdr.VENDOR_TYPE,
         hdr.VENDOR_ID,
         --to_date(hdr.VENDOR_DOCUMENT_DATE, 'YYYYMMDDHH24MISS') VENDOR_DOCUMENT_DATE ,
         hdr.VENDOR_DOCUMENT_DATE,
         to_number(hdr.ORDER_NUMBER_RTV_NUMBER) ORDER_NUMBER_RTV_NUMBER,
         to_number(hdr.LOCATION) LOCATION,
         hdr.LOCATION_TYPE,
         hdr.TERMS,
         hdr.DUE_DATE,
        -- to_date(hdr.DUE_DATE, 'YYYYMMDDHH24MISS') DUE_DATE ,
         hdr.PAYMENT_METHOD,
         hdr.CURRENCY_CODE,
         to_number(hdr.EXCHANGE_RATE) EXCHANGE_RATE,
         hdr.SIGN_INDICATOR_COST,
         to_number(hdr.TOTAL_COST)/10000 TOTAL_COST,
         hdr.SIGN_INDICATOR_VAT,
         to_number(hdr.TOTAL_VAT_AMOUNT)/10000 TOTAL_VAT_AMOUNT ,
         hdr.SIGN_INDICATOR_QTY,
         to_number(hdr.TOTAL_QUANTITY)/10000 TOTAL_QUANTITY,
         hdr.SIGN_INDICATOR_DISC,
         to_number(hdr.TOTAL_DISCOUNT) TOTAL_DISCOUNT,
         hdr.FREIGHT_TYPE,
         hdr.PAID_IND,
         hdr.MULTI_LOCATION,
         hdr.CONSIGNMENT_INDICATOR,
         to_number(hdr.DEAL_ID) DEAL_ID,
         hdr.DEAL_APPROVAL_INDICATOR,
         hdr.RTV_INDICATOR,
         hdr.CUSTOM_DOCUMENT_REFERENCE_1,
         hdr.CUSTOM_DOCUMENT_REFERENCE_2,
         hdr.CUSTOM_DOCUMENT_REFERENCE_3,
         hdr.CUSTOM_DOCUMENT_REFERENCE_4,
         to_number(hdr.CROSS_REFERENCE_DOC_NUMBER) CROSS_REFERENCE_DOC_NUMBER
    FROM SMR_RMS_INT_EDI_810_hdr_stg hdr
ORDER BY TO_NUMBER (LINE_ID) ASC;
 
    cursor c_dtl is
     SELECT RECORD_DESCRIPTOR,
              LINE_ID,
              TRANSACTION_NUMBER,
              UPC,
              to_number(UPC_SUPPLEMENT) UPC_SUPPLEMENT,
              ITEM,
              VPN,
              SIGN_INDICATOR_QTY,
              to_number(ORIGINALDOCUMENT_QUANTITY)/10000 ORIGINALDOCUMENT_QUANTITY,
              SIGN_INDICATOR,
              to_number(ORIGINAL_UNIT_COST)/10000 ORIGINAL_UNIT_COST,
              ORIGINAL_VAT_CODE,
              to_number(ORIGINAL_VAT_RATE)/10000 ORIGINAL_VAT_RATE,
              SIGN_INDICATOR_VAT,
              to_number(TOTAL_ALLOWANCE)/10000 TOTAL_ALLOWANCE 
         FROM SMR_RMS_INT_EDI_810_DTL_stg
        WHERE  ( ( line_id BETWEEN L_start_line_id AND L_end_line_id and L_end_line_id is not null)
                  or ( line_id > L_start_line_id  and L_end_line_id is null ) )
ORDER BY TO_NUMBER (LINE_ID) ASC;

   cursor c_guid is
          select   interface_id
               from SMR_RMS_INT_TYPE
       where interface_name = 'EDI_810';

BEGIN

   for r1 in c_hdr loop
      L_start_line_id   := r1.LINE_ID;
      L_end_line_id   := r1.NEXT_LINE_ID;
        open c_guid;
       fetch c_guid into  L_interface_id;
       close c_guid;
          L_record_id := L_record_id + 1;
          if SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID( O_error_message, L_interface_id, L_guid ) = FALSE then
      	       RAISE guid_err;
          end if;
      insert into SMR_RMS_INT_EDI_810_HDR_IMP (RECORD_ID,
					       GROUP_ID,
					       DOCUMENT_TYPE,
					       VENDOR_DOCUMENT_NUMBER,
					       VENDOR_TYPE,
					       VENDOR_ID,
					       VENDOR_DOCUMENT_DATE,
					       ORDER_NUMBER,
					       LOCATION,
					       LOCATION_TYPE,
					       TERMS,
					       DUE_DATE,
					       PAYMENT_METHOD,
					       CURRENCY_CODE,
					       EXCHANGE_RATE,
					       TOTAL_COST,
					       SIGN_INDICATOR_COST,
					       TOTAL_VAT_AMOUNT,
					       SIGN_INDICATOR_VAT,
					       TOTAL_QUANTITY,
					       SIGN_INDICATOR_QTY,
					       TOTAL_DISCOUNT,
					       SIGN_INDICATOR_DISC,
					       FREIGHT_TYPE,
					       PAID_IND,
					       MULTI_LOCATION,
					       CONSIGNMENT_INDICATOR,
					       DEAL_ID,
					       DEAL_APPROVAL_INDICATOR,
					       RTV_INDICATOR,
					       CUSTOM_DOCUMENT_REFERENCE_1,
					       CUSTOM_DOCUMENT_REFERENCE_2,
					       CUSTOM_DOCUMENT_REFERENCE_3,
					       CUSTOM_DOCUMENT_REFERENCE_4,
					       CROSS_REF_DOCUMENT_NUMBER,
					       PROCESSED,
					       CREATE_DATE,
					       PROCESSED_DATE,
					       ERROR_IND)
			              values   (L_record_id,
			                        L_guid,
                                                r1.DOCUMENT_TYPE,
						 r1.VENDOR_DOCUMENT_NUMBER,
						 r1.VENDOR_TYPE,
						 r1.VENDOR_ID,
						 r1.VENDOR_DOCUMENT_DATE,
						 r1.ORDER_NUMBER_RTV_NUMBER,
						 r1.LOCATION,
						 r1.LOCATION_TYPE,
						 r1.TERMS,
						 r1.DUE_DATE,
						 r1.PAYMENT_METHOD,
						 r1.CURRENCY_CODE,
						 r1.EXCHANGE_RATE,
						 r1.TOTAL_COST,
						  r1.SIGN_INDICATOR_COST,
						 r1.TOTAL_VAT_AMOUNT,
						 r1.SIGN_INDICATOR_VAT,
						 r1.TOTAL_QUANTITY,
						  r1.SIGN_INDICATOR_QTY,
						   r1.TOTAL_DISCOUNT,
						r1.SIGN_INDICATOR_DISC,
						 r1.FREIGHT_TYPE,
						 r1.PAID_IND,
						 r1.MULTI_LOCATION,
						 r1.CONSIGNMENT_INDICATOR,
						 r1.DEAL_ID,
						 r1.DEAL_APPROVAL_INDICATOR,
						 r1.RTV_INDICATOR,
						 r1.CUSTOM_DOCUMENT_REFERENCE_1,
						 r1.CUSTOM_DOCUMENT_REFERENCE_2,
						 r1.CUSTOM_DOCUMENT_REFERENCE_3,
						 r1.CUSTOM_DOCUMENT_REFERENCE_4,
                                                 r1.CROSS_REFERENCE_DOC_NUMBER,
                                                 'N',
						 sysdate,
						 null,
					        'N' );
      
     for r2 in c_dtl loop
             insert into SMR_RMS_INT_EDI_810_DTL_IMP (
						    RECORD_ID,
						    GROUP_ID,
						    UPC,
						    UPC_SUPPLEMENT,
						    ITEM,
						    VPN,
						    SIGN_INDICATOR_QTY,
						    ORIGINAL_DOCUMENT_QUANTITY,
						    SIGN_INDICATOR_COST,
						    ORIGINAL_UNIT_COST,
						    ORIGINAL_VAT_CODE,
						    ORIGINAL_VAT_RATE,
						    SIGN_INDICATOR_VAT,
						    TOTAL_ALLOWANCE,
						    PROCESSED,
						    CREATE_DATE,
						    PROCESSED_DATE,
						    ERROR_IND )
                                           values ( L_record_id,
			                            L_guid,
			                            r2.UPC,
					            r2.UPC_SUPPLEMENT,
					            r2.ITEM,
					            r2.VPN,
					            r2.SIGN_INDICATOR_QTY,
					            r2.ORIGINALDOCUMENT_QUANTITY,
					            r2.SIGN_INDICATOR,
					            r2.ORIGINAL_UNIT_COST,
					            r2.ORIGINAL_VAT_CODE,
					            r2.ORIGINAL_VAT_RATE,
					            r2.SIGN_INDICATOR_VAT,
                                                    r2.TOTAL_ALLOWANCE,
                                                    'N',
						    sysdate,
						    null,
						    'N');

     end loop;
   
   end loop;


 commit;
  return TRUE;
EXCEPTION
    when guid_err then
         O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
	                                           SQLERRM,
	                                           L_program,
                                                   NULL);
         RAISE;
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                          SQLERRM,
                                          L_program,
                                          NULL);
    return FALSE;
END EDI810_PRE;

------------------------------------------------------------------------------------
END SMR_RMS_INT_EDI_810;
/
