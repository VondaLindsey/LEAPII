Description: DDL for EDI 850/860;
  Create table SMR_PO_EDI_850_860_HDR_EXP
  Create table SMR_PO_EDI_850_860_DTL_EXP 
  Create index SMR_PO_EDI_850_860_i1 on SMR_PO_EDI_850_860_HDR_EXP(PO_NMBR);
  Create index SMR_PO_EDI_850_860_i2 on SMR_PO_EDI_850_860_DTL_EXP(REC_TYPE1,PO_NMBR,ITEM_SKU_NMBR,REC_SEQ);
  Insert into restart_control 'smr_edi850sdq'
  Insert into restart_program_status
  Alter table OLR_SMR_ORD_EXTRACT_117633  modify  (order_no number(10)); /*existing; 860_cleanup*/
  Create synonyms
  CREATE SEQUENCE  "RMS13"."RMS_SMR_EDI_850_860_SEQ" 


