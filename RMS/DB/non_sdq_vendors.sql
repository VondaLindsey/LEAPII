drop table smr_no_sdq_edi_sup;
create table smr_no_sdq_edi_sup( supplier number(10) not null);
create index smr_no_sdq_edi_sup_i1 on smr_no_sdq_edi_sup( supplier );

CREATE OR REPLACE PUBLIC SYNONYM SMR_NO_SDQ_EDI_SUP FOR RMS13.SMR_NO_SDQ_EDI_SUP;
GRANT SELECT ON SMR_NO_SDQ_EDI_SUP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;
GRANT DELETE, INSERT, UPDATE ON SMR_NO_SDQ_EDI_SUP TO RMS13_UPDATE;  

