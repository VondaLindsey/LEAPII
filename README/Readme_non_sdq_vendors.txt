Description: DDL required to implement Non-SDQ vendors (table-driven)
  Create table smr_no_sdq_edi_sup
  Create index smr_no_sdq_edi_sup_i1 on smr_no_sdq_edi_sup( supplier ); 
  CREATE OR REPLACE PUBLIC SYNONYM SMR_NO_SDQ_EDI_SUP FOR RMS13.SMR_NO_SDQ_EDI_SUP;
  GRANT SELECT ON SMR_NO_SDQ_EDI_SUP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;
  GRANT DELETE, INSERT, UPDATE ON SMR_NO_SDQ_EDI_SUP TO RMS13_UPDATE;  

