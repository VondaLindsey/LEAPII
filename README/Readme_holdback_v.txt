Description: DDL to implement ALC Holdback;
   Create view smr_alc_holdback_v
   Create table smr_alloc_wh_hold_back
   CREATE SYNONYM SMR_ALLOC_WH_HOLD_BACK FOR RMS13.SMR_ALLOC_WH_HOLD_BACK;
   GRANT SELECT ON SMR_ALLOC_WH_HOLD_BACK TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;
   GRANT DELETE, INSERT, UPDATE ON SMR_ALLOC_WH_HOLD_BACK TO RMS13_UPDATE;  
