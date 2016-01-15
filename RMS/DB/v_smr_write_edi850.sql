create or replace view v_smr_write_edi850 as (
select group_id,record_id,EDI850 from (
  select group_id,record_id,
   /*H1*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_TYPE                                ||
                   PO_NMBR                                ||
                   PO_PURPOSE_CODE                        ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
 rpad(nvl(to_char( MASTER_PO_NMBR       ),' ') ,  9, ' ' )||
                   VENDOR_NMBR_REF                        || /* 'IA'            */
             lpad( VENDOR_NMBR                 ,  9, '0' )||
                   DEPT_NMBR_REF                          || /* 'DP'            */
             lpad( DEPT_NMBR                   ,  3, '0' )||
                   BUYER_NMBR_REF                         || /* 'BY'            */
                   BUYER_FNCTN_CODE                       || /* 'BD'            */
             lpad( BUYER_NMBR                  ,  3, '0' )||
             rpad( BUYER_CONTACT_NAME          , 60, ' ' )||
                   BUYER_COMM_QUALFR                      || /* 'TE'            */
 rpad(nvl(to_char( BUYER_PHONE_NMBR     ),' ') , 80, ' ' )||
                   DC_FUNCTION_CODE                       || /* 'DC'            */
 rpad(nvl(to_char( DC_CONTACT_NAME      ),' ') , 60, ' ' )||
                   DC_COMM_QUALIFER                       || /* 'TE'            */
 rpad(nvl(to_char( DC_PHONE_NMBR        ),' ') , 80, ' ' )||
                   CASH_REQ_CODE1                         || /* 'NS'            */
                   CASH_REQ_CODE2                         || /* 'SC'            */
 rpad(nvl(to_char( DELIVERY_INSTRUCT    ),' ') , 35, ' ' )||
 rpad(nvl(to_char( SPECIAL_FREIGHT_DESC ),' ') , 20, ' ' )||
 rpad(nvl(to_char( DISCOUNT_DESC        ),' ') , 30, ' ' )|| /* termsCode       */
             lpad( TOTAL_QTY_PO                ,  9, '0' )|| 
                   PO_APPROVE_DATE                        ||
                   PO_REQUESTED_SHIP                      || /* '010'           */
                   PO_SHIP_DATE                           || 
                   PO_RCV_DATE                            || /* '00000000'      */
                   PO_CANCEL_AFTER                        || /* '001'           */
                   PO_CANCEL_DATE                         || /* newNotAfterDate */
         rpad(nvl( PO_PROMO              ,' ') ,  3, ' ' )|| 
             lpad( PO_PROMO_DATE               ,  8, '0' )||
                   TERMS_ID_QUALIFER                      || /* 'ME'            */
             rpad( TERMS_OF_PURCH1             ,170, ' ' )||
             rpad( TERMS_OF_PURCH2             ,170, ' ' ),855) EDI850
  from SMR_PO_EDI_850_860_HDR_EXP where rec_type1 = 'S850H1'
UNION ALL
  select group_id,record_id,
   /*H2*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_NMBR                                ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
                   CHARGE_IND                             || /* 'N'             */
                   VICS                                   || /* 'VI'            */
         rpad(nvl( NEW_STORE_RUSH        ,' ') , 10, ' ' )|| 
         rpad(nvl( SAC_DESC              ,' ') , 40, ' ' ),97) EDI850
  from SMR_PO_EDI_850_860_HDR_EXP where rec_type1 = 'S850H2'
UNION ALL
  select group_id,record_id,
   /*H3*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_NMBR                                ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
                   DESC_TYPE                              || /* 'F'             */
         rpad(nvl( SPLIT_COMMENTS        ,' ') , 50, ' ' ),95) EDI850
  from SMR_PO_EDI_850_860_HDR_EXP where rec_type1 = 'S850H3'
UNION ALL
  select group_id,record_id,
   /*H4*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_NMBR                                ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
                   SHIP_TO_MARK_FOR                       ||
         rpad(nvl( ADDRESS1              ,' ') , 55, ' ' )|| 
         rpad(nvl( ADDRESS2              ,' ') , 55, ' ' )|| 
         rpad(nvl( CITY                  ,' ') , 30, ' ' )|| 
         rpad(nvl( STATE                  ,' ') , 2, ' ' )|| 
         rpad(nvl( ZIP                   ,' ') , 10, ' ' )|| 
         rpad(nvl( COUNTRY               ,' ') ,  3, ' ' )|| 
         rpad(nvl( WH_DESC               ,' ') , 25, ' ' ),226) EDI850
  from SMR_PO_EDI_850_860_HDR_EXP where rec_type1 = 'S850H4' /* RL, SA */
UNION ALL  
  select group_id,record_id,
   /*VP*/    rpad( REC_TYPE1                              ||				
                   REC_TYPE2                              ||' '     ||			
             lpad( REC_SEQ                     ,  4, '0' )||				
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||			
             lpad( COMPANY_ID                  ,  3, '0' )||				
                   PO_NMBR                                ||				
             lpad( DC_STORE_NMBR               ,  5, '0' )||				
             lpad( PACK_SKU_NMBR               , 11, '0' )||				  
             lpad( DETAIL_REC_SUB_SEL          ,  5, '0' )|| /* 1               */	
         rpad(nvl( VPN                   ,' ') , 15, ' ' )|| 				  
             lpad( nvl(PACK_UNITS,'0')         ,  8, '0' )||				
                   UOM_IDENTIFIER                         ||                   		
             lpad( PACK_UNIT_COST              , 10, '0' )||				  
             decode(PACK_UPC,null,lpad(PACK_UPC, 15, ' ' ),lpad( PACK_UPC, 15, '0' ))||				
             lpad( TOTAL_SUBLINE_QTY           ,  9, '0' ),119) EDI850				
    from SMR_PO_EDI_850_860_DTL_EXP where rec_type1 = 'SPOVND' 
UNION ALL  
  select group_id,record_id,
   /*D4*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_NMBR                                ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
             lpad( ITEM_SKU_NMBR               , 11, '0' )||
             lpad( ITEM_STORE_NMBR             ,  9, '0' )||
             lpad( DETAIL_REC_SUB_SEL          ,  5, '0' )|| /* 1               */
         rpad(nvl( VPN                   ,' ') , 15, ' ' )|| 
             lpad( ITEM_QTY                    ,  7, '0' )||
                   UOM_IDENTIFIER                         ||                   
             lpad( UNIT_COST                   , 10, '0' )||
             lpad( UPC                         , 15, '0' )||
                   RETAIL_PRICE_ID                        || /* 'MSR'           */
             lpad( RETAIL_PRICE                , 10, '0' )|| 
                   BUYER_COLOR_QUALIFIER                  || /* 'BO'            */
         rpad(nvl( BUYER_COLOR_DESC      ,' ') , 15, ' ' )|| 
                   BUYER_SIZE_QUALIFIER                   || /* 'IZ'            */
         rpad(nvl( BUYER_SIZE_DESC       ,' ') , 15, ' ' )|| 
                   COMPARE_TO_PRICE_ID                    || /* 'MSR'           */
             lpad( COMPARE_TO_PRICE            , 10, '0' ),178) EDI850
  from SMR_PO_EDI_850_860_DTL_EXP where rec_type1 = 'S850D4' 
UNION ALL
  select group_id,record_id,
   /*D1*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_NMBR                                ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
             lpad( ITEM_SKU_NMBR               , 11, '0' )||
             lpad( ITEM_STORE_NMBR             ,  9, '0' )||
             lpad( DETAIL_REC_SUB_SEL          ,  5, '0' )|| /* 1               */
         rpad(nvl( VPN                   ,' ') , 15, ' ' )|| 
             lpad( nvl(ITEM_QTY,'0')           ,  7, '0' )||
                   UOM_IDENTIFIER                         ||                   
             lpad( UNIT_COST                   , 10, '0' )||
             lpad( UPC                         , 15, '0' )||
                   RETAIL_PRICE_ID                        || /* 'MSR'           */
             lpad( RETAIL_PRICE                , 10, '0' )|| 
                   BUYER_COLOR_QUALIFIER                  || /* 'BO'            */
         rpad(nvl( BUYER_COLOR_DESC      ,' ') , 15, ' ' )|| 
                   BUYER_SIZE_QUALIFIER                   || /* 'IZ'            */
         rpad(nvl( BUYER_SIZE_DESC       ,' ') , 15, ' ' )|| 
                   COMPARE_TO_PRICE_ID                    || /* 'MSR'           */
             lpad( nvl(COMPARE_TO_PRICE  ,'0') , 10, '0' ),178) EDI850
  from SMR_PO_EDI_850_860_DTL_EXP where rec_type1 = 'S850D1' 
UNION ALL
  select group_id,record_id,
   /*D2*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_NMBR                                ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
             lpad( ITEM_SKU_NMBR               , 11, '0' )||
             lpad( UPC                         , 15, '0' )||
         rpad(nvl( VPN                   ,' ') , 15, ' ' )|| 
             lpad( DETAIL_REC_SUB_SEL          ,  5, '0' )|| /* 1               */
                   CHARGE_IND                             || /* 'N'             */
                   VICS                                   || /* 'VI'            */
         rpad(nvl( TCKT_HANG_CODE        ,' ') , 10, ' ' )|| 
         rpad(nvl( TCKT_HANG_DESC        ,' ') , 80, ' ' ),113) EDI850
  from SMR_PO_EDI_850_860_DTL_EXP where rec_type1 = 'S850D2'
UNION ALL
  select group_id,record_id,
   /*D3*/    rpad( REC_TYPE1                              ||
                   REC_TYPE2                              ||' '     ||
             lpad( REC_SEQ                     ,  4, '0' )||
             lpad( SUPPLIER_NMBR               ,  9, '0' )||'      '||
             lpad( COMPANY_ID                  ,  3, '0' )||
                   PO_NMBR                                ||
             lpad( DC_STORE_NMBR               ,  5, '0' )||
             lpad( ITEM_SKU_NMBR               , 11, '0' )||
             decode(UPC, null, lpad( UPC       , 15, ' ' ),lpad( UPC, 15, '0' ))||				
         rpad(nvl( VPN                   ,' ') , 15, ' ' )|| 
                   SDQ_TEXT                               || /* 'SDQ'           */
                   UOM_IDENTIFIER                         ||                   
        lpad( decode( SDQ1_STORE, null, nvl(STORE ,'0'), SDQ1_STORE),  5, '0' )|| 
        lpad( decode( SDQ1_STORE_QUANTITY, null, nvl(STORE_QUANTITY ,'0'), SDQ1_STORE_QUANTITY),  7, '0' )||' '     ||
        lpad( nvl( SDQ2_STORE            ,'0') ,  5, '0' )|| 
        lpad( nvl( SDQ2_STORE_QUANTITY   ,'0') ,  7, '0' )||' '     ||
        lpad( nvl( SDQ3_STORE            ,'0') ,  5, '0' )|| 
        lpad( nvl( SDQ3_STORE_QUANTITY   ,'0') ,  7, '0' )||' '     ||
        lpad( nvl( SDQ4_STORE            ,'0') ,  5, '0' )|| 
        lpad( nvl( SDQ4_STORE_QUANTITY   ,'0') ,  7, '0' )||' '     ||
        lpad( nvl( SDQ5_STORE            ,'0') ,  5, '0' )|| 
        lpad( nvl( SDQ5_STORE_QUANTITY   ,'0') ,  7, '0' )||' '     ||
        lpad( nvl( SDQ6_STORE            ,'0') ,  5, '0' )|| 
        lpad( nvl( SDQ6_STORE_QUANTITY   ,'0') ,  7, '0' )||' '     ||
        lpad( nvl( SDQ7_STORE            ,'0') ,  5, '0' )|| 
        lpad( nvl( SDQ7_STORE_QUANTITY   ,'0') ,  7, '0' )||' '     ||
        lpad( nvl( SDQ8_STORE            ,'0') ,  5, '0' )|| 
        lpad( nvl( SDQ8_STORE_QUANTITY   ,'0') ,  7, '0' )||' ',194) EDI850
  from SMR_PO_EDI_850_860_DTL_EXP where rec_type1 = 'S850D3'));
  

/**
-- before group_id,record_id; sort based on order_no, heasder_recs, then detail recs.

select * from v_smr_write_edi850  
  order by decode(substr(EDI850, 1, 6),'S850H1',substr(EDI850,33, 9),substr(EDI850,31,9)), -- order_no
           decode(substr(EDI850, 1, 6),'S850H1',1,                                         -- H1 first
                                       'S850H2',substr(EDI850, 9, 4),                      -- rec_seq 
                                       'S850H3',substr(EDI850, 9, 4),                      -- rec_seq 
                                       'S850H4',7,null),                                   -- hdr recs
           substr(EDI850,45,11),                                                           -- item_no 
           decode(substr(EDI850, 1, 6),'S850D1',9,                                         -- dtl recs
                                       'S850D2',substr(EDI850, 9, 4)+9,                    -- rec_seq 
                                       'S850D3',substr(EDI850, 9, 4)+9,14)                 -- rec_seq ;

-- sort after adding group_id,record_id;

set pages 0
set termout off
set verify off
set feedback off
set echo off
set lines 1000
spool RMS_PO.dat
select EDI850 from v_smr_write_edi850 order by group_id,record_id;
spool off;
set pages 5000
set termout on
set echo on
set feedback on
set verify on

**/

drop public synonym v_smr_write_edi850;   
create public synonym v_smr_write_edi850 for RMS13.v_smr_write_edi850;
grant select on v_smr_write_edi850 to DEVELOPER,RMS13_SELECT;

