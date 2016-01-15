-- The script run_all_sql.sql contains all the DB objects that were impacted by Leap Changes
-- The script contains all the Objects that needs to be modified/Created and in the Sequnce they need to be Executed.
-- The script is Called from the Deployment script to create all the OBjects 

set echo on
set serveroutput on
set feedback on
set verify on

-- DDL scripts for creating new tables required for Leap and any modification to the existing Tables
-- Script to increase the Order_no field to 10 digit
@order_no_precision_mod.sql
-- Script for Creation of Tables for EDI 810 interface
@smr_edi810_table_script.sql
-- Script for Modification of ORDER_TBL Type to increase the Order_no field.
@SMR_ORDER_TBL.sql
-- Script for Modification of RIB_DSDDeals_REC Type to increase the Order_no field.
@SMR_RIB_DSDDeals_REC.sql
-- Script for Modification of RIB_XAlloc_REC Type to increase the Order_no field.
@SMR_RIB_XAlloc_REC.sql
-- Script for Modification of OBJ_REIM_RCPT_WRITEOFF_REC Type to increase the Order_no field.
@SMR_OBJ_REIM_RCPT_WRITEOFF_REC.sql
-- Script for Creation of Interface tables for Allocation and transfers
@smr_leap2_wa_alloc_tsf_tables.sql
-- Table Creation Script for Interface between RMS and WA.  
@SMR_Interface_Tables.sql
-- Script for table creation for Leap Changes 
@SMR_RMS_LEAP_DDL.sql

-- Scripts for Creation of New Sequences required for Leap.
@leap_interface_sequence.sql

-- Scripts for Creation/Modification of Database triggers required For Leap

-- Script for creation trigger on transfer table to Interface data to WA.
@smr_leap2_wa_tsf_trigger.sql
-- Script for creation trigger on allocation table to Interface data to WA.
@smr_leap2_wa_alloc_trigger.sql
-- Script for creation trigger on Item_master table to Interfacing Vendor Pack data to WA.
@SMR_RMS_TABLE_IEMVP_AIUD.trg
-- Script for creation trigger on RTV table to Interface data to WA.
@SMR_RMS_TABLE_RHD_AIUD.trg
-- Script for creation trigger on Transfer table to Interface RTW data to WA.
@SMR_RMS_TABLE_THD_AIUD.trg
-- Script for creation trigger on Allocation Alc table for PO process.
@smr_alc_table_aa_aiur.trg
-- Script for creation trigger on smr_po_edi_850_860_hdr_exp to interface PO data to WA.
@smr_wa_po_hdr_if_aiur.trg
-- Script for creation trigger on smr_po_edi_850_860_Dtl_exp to interface PO data to WA.
@smr_wa_po_dtl_if_aiur.trg

-- Insert script on Nav_elements and for smr_ordfind form. 
@smr_ordfind_ins.sql
-- Update script on wh_attributes to update wh_type_code. 
@wh_attributes.sql
-- Script to create view smr_alc_holdback_v and PO holdback tables
@holdback_v.sql
-- Script for table creation used for PO split process.
@split_transform_obj.sql
-- Script for table creation used for PO alloc Intent.
@alloc_intent_cre.sql
-- Script for table creation used for Maintaining non SDQ vendors.
@non_sdq_vendors.sql
-- Script for table creation used for PO Interface to WA.
@wa_po_cre.sql
-- Script for table creation used for PO 850/860 data.
@EDI_850_860_cre.sql
-- Script modify the existing view v_smr_stand_alone_wh.
@v_smr_stand_alone_wh.sql
-- Script to create a View to be used for 850 file generation from Interface tables.
@v_smr_write_edi850.sql

-- Scripts for Creation/Modification of Package Specification required For Leap
@SMR_LEAP_ASN_SQL.pls
@SMR_VENDOR_ASN_SQL.pls
@SMR_WH_ADJ_SQL.pls
@SMR_WH_RECEIVING.pls
@SMR_WH_SHIP_SQL.pls
@SMR_LEAP_INTERFACE_SQL.pls
@smr_rms_int_edi_810_prcs.pks

-- Scripts for Creation/Modification of Package Body required For Leap
-- Script to create package SMR_LEAP_INTERFACE_SQL - Used for PO process and RTV, RTW and VP interface to WA
@SMR_LEAP_INTERFACE_SQL.plb
-- Script to modify package FIX_CLOSE_SMR_SDC_944 to accommodate Order_no field Increase
@FIX_CLOSE_SMR_SDC_944.pkb
-- Script to modify package ONLY_856_SMR_SDC_944 to accommodate Order_no field Increase
@ONLY_856_SMR_SDC_944.pkb
-- Script to modify package SMR_SDC_944 to accommodate Order_no field Increase
@SMR_SDC_944.pkb
-- Script to create Package smr_rms_int_edi_810_prcs used for EDI 810 Process
@smr_rms_int_edi_810_prcs.pkb

-- Script to create Package SMR_LEAP_ASN_SQL used for Processing Vendor ASN into RMS
@SMR_LEAP_ASN_SQL.plb
-- Script to create Package SMR_VENDOR_ASN_SQL used for Loading Vendor ASN into RMS
@SMR_VENDOR_ASN_SQL.plb
-- Script to Modify Package smr_custom_rca used for Receipt Adjsutment Process 
@smr_custom_rca.plb
-- Script to create Package SMR_WH_ADJ_SQL used for Loading Adjustments from WA into RMS
@SMR_WH_ADJ_SQL.plb
-- Script to create Package SMR_WH_RECEIVING used for Loading Receipts from WA into RMS
@SMR_WH_RECEIVING.plb
-- Script to create Package SMR_WH_SHIP_SQL used for Loading Shipments from WA into RMS
@SMR_WH_SHIP_SQL.plb
-- Script to Modify Package SMR_PACK_SQL to allow Create from Existing Functionality for VP
@SMR_PACK_SQL.plb
-- Script to Modify Package SMR_MASS_RTV_SQL to remove hard coding on RTV Reason Code.
@SMR_MASS_RTV_SQL.plb
-- Script to Modify Package SMR_MANUAL_944_SQL to Fix the Carton Receiving Screen for Leap.
@SMR_MANUAL_944_SQL.plb
-- Script to Modify On order computation to include only orders with "Include On Order" flag set.
@SMR_E3_EXTRACT_SQL.plb

-- DML statements for updating the data in Tables that are required for Leap.
@SMR_RMS_LEAP_DML.sql

exit;