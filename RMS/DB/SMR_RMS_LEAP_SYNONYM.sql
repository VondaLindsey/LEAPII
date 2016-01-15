-------------------------------------------------------
-- Modification History
-- Version Date      Developer   Issue/CR      Description
-- ======= ========= =========== ========   ===============================================
-- 1.0    10-Jul-15  Murali        LEAP2        Public Synonym for Packages           
-------------------------------------------------------------------------------------------
Prompt Create Public Synonym for SMR_LEAP_ASN_SQL
create or replace public synonym SMR_LEAP_ASN_SQL for SMR_LEAP_ASN_SQL;

grant execute on SMR_LEAP_ASN_SQL TO RMS13_UPDATE;

----------------------------------------------------------------------------------------
Prompt Create Public Synonym for SMR_VENDOR_ASN_SQL
create or replace public synonym SMR_VENDOR_ASN_SQL for SMR_VENDOR_ASN_SQL;

grant execute on SMR_VENDOR_ASN_SQL TO RMS13_UPDATE;

----------------------------------------------------------------------------------------
Prompt Create Public Synonym for SMR_WH_ADJ_SQL
create or replace public synonym SMR_WH_ADJ_SQL for SMR_WH_ADJ_SQL;

grant execute on SMR_WH_ADJ_SQL TO RMS13_UPDATE;

----------------------------------------------------------------------------------------
Prompt Create Public Synonym for SMR_WH_RECEIVING
create or replace public synonym SMR_WH_RECEIVING for SMR_WH_RECEIVING;

grant execute on SMR_WH_RECEIVING TO RMS13_UPDATE;

----------------------------------------------------------------------------------------
Prompt Create Public Synonym for SMR_WH_SHIP_SQL
create or replace public synonym SMR_WH_SHIP_SQL for SMR_WH_SHIP_SQL;

grant execute on SMR_WH_SHIP_SQL TO RMS13_UPDATE;

----------------------------------------------------------------------------------------
Prompt Create Public Synonym for SMR_LEAP_INTERFACE_SQL
create or replace public synonym SMR_LEAP_INTERFACE_SQL for SMR_LEAP_INTERFACE_SQL;

grant execute on SMR_LEAP_INTERFACE_SQL TO RMS13_UPDATE;

----------------------------------------------------------------------------------------
Prompt Create Public Synonym for SMR_RMS_INT_EDI_810
create or replace public synonym SMR_RMS_INT_EDI_810 for SMR_RMS_INT_EDI_810;

grant execute on SMR_RMS_INT_EDI_810 TO RMS13_UPDATE;