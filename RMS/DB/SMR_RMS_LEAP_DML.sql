-------------------------------------------------------
-- Modification History
-- Version Date      Developer   Issue/CR      Description
-- ======= ========= =========== ========   ===============================================
-- 1.0    10-May-15  Murali        LEAP2        Creation of Tables.            
-------------------------------------------------------------------------------------------

-- Inserting into SMR_ADJ_REASON_CODE the WMS and RMS reason code mapping for adjustments
prompt Deleteing table SMR_ADJ_REASON_CODE...
delete from RMS13.SMR_ADJ_REASON_CODE;

prompt Inserting table SMR_ADJ_REASON_CODE...
insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (550, 'Cycle Count Adj - WMS', 851, 0);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (540, 'Shrink Adj - WMS', 760, 0);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (541, 'Samples Adj - WMS', 761, 0);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (542, 'Donations Adj - WMS', 762, 0);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (543, 'MOS Adj- WMS', 763, 0);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (523, 'Damages Adj (Scrap) - WMS', 544, 0);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (549, 'Adjust Inventory Location - WMS', 852, 0);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (545, 'Hold by LP - WMS', 720, 3);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (546, 'Hold by ItemS WMS', 700, 3);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (547, 'Release by LP - WMS', 770, 3);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (548, 'Release by Item - WMS', 750, 3);

insert into SMR_ADJ_REASON_CODE (REASON_CODE, REASON_DESC, WMS_REASON_CODE, INV_STATUS)
values (255, 'Receipt Adjustment', 255, 5);

commit;

----------------------------------------------------------------------------------------------
-- Inserting into nav elements for new forms 

Prompt Delete from Nav folders

delete from nav_element_mode_role where element in ('smr_wh_rua','smr_810_interface');

delete from nav_element_mode where element in ('smr_wh_rua','smr_810_interface');

delete from nav_element where element in ('smr_wh_rua','smr_810_interface');

delete from nav_folder where folder in ('SMR Warehouse RUA');

commit;

prompt Inserting table nav_folder...

insert into rms13.nav_folder (FOLDER, FOLDER_NAME, PARENT_FOLDER, USER_ID, SALES_AUDIT_IND, FINANCIAL_O_IND, FINANCIAL_P_IND, FINANCIAL_NULL_IND, CONTRACT_IND, VAT_IND, IMPORT_IND, ELC_IND)
values ('SMR Warehouse RUA', 'SMR Warehouse RUA', 'RECEIVING', null, null, null, null, null, null, null, null, null);


prompt Inserting table nav_element...

insert into rms13.nav_element (ELEMENT, ELEMENT_TYPE, COMPONENT)
values ('smr_810_interface', 'F', 'RMS');

insert into rms13.nav_element (ELEMENT, ELEMENT_TYPE, COMPONENT)
values ('smr_wh_rua', 'F', 'RMS');

insert into rms13.nav_element (ELEMENT, ELEMENT_TYPE, COMPONENT)
values ('smr_rec_corrections', 'F', 'RMS');

prompt Inserting table nav_element_mode...

insert into rms13.nav_element_mode (ELEMENT, NAV_MODE, FOLDER, ELEMENT_MODE_NAME, USER_ID, FINANCIAL_O_IND, FINANCIAL_P_IND, FINANCIAL_NULL_IND, CONTRACT_IND, VAT_IND, IMPORT_IND, MULTICHANNEL_IND)
values ('smr_810_interface', '--DEFAULT--', 'DEPT_DETAILS', 'SMR EDI 810 Interface', null, null, null, null, null, null, null, null);

insert into rms13.nav_element_mode (ELEMENT, NAV_MODE, FOLDER, ELEMENT_MODE_NAME, USER_ID, FINANCIAL_O_IND, FINANCIAL_P_IND, FINANCIAL_NULL_IND, CONTRACT_IND, VAT_IND, IMPORT_IND, MULTICHANNEL_IND)
values ('smr_wh_rua', 'EDIT', 'SMR Warehouse RUA', 'Edit', null, null, null, null, null, null, null, null);

insert into rms13.nav_element_mode (ELEMENT, NAV_MODE, FOLDER, ELEMENT_MODE_NAME, USER_ID, FINANCIAL_O_IND, FINANCIAL_P_IND, FINANCIAL_NULL_IND, CONTRACT_IND, VAT_IND, IMPORT_IND, MULTICHANNEL_IND)
values ('smr_wh_rua', 'VIEW', 'SMR Warehouse RUA', 'View', null, null, null, null, null, null, null, null);

insert into nav_element_mode (ELEMENT, NAV_MODE, FOLDER, ELEMENT_MODE_NAME, USER_ID, FINANCIAL_O_IND, FINANCIAL_P_IND, FINANCIAL_NULL_IND, CONTRACT_IND, VAT_IND, IMPORT_IND, MULTICHANNEL_IND)
values ('smr_rec_corrections', '--DEFAULT--', 'RECEIVING', 'SMR Rec Error Correction(Leap)', null, null, null, null, null, null, null, null);

prompt Inserting table nav_element_mode_role...

insert into rms13.nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_810_interface', '--DEFAULT--', 'DEPT_DETAILS', 'DEVELOPER');

insert into rms13.nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_wh_rua', 'EDIT', 'SMR Warehouse RUA', 'DEVELOPER');

insert into rms13.nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_wh_rua', 'VIEW', 'SMR Warehouse RUA', 'DEVELOPER');

insert into rms13.nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_810_interface', '--DEFAULT--', 'DEPT_DETAILS', 'FINANCE');

insert into rms13.nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_wh_rua', 'VIEW', 'SMR Warehouse RUA', 'FINANCE');

insert into rms13.nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_wh_rua', 'EDIT', 'SMR Warehouse RUA', 'INVMGT');

insert into rms13.nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_wh_rua', 'VIEW', 'SMR Warehouse RUA', 'INVMGT');

insert into nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_rec_corrections', '--DEFAULT--', 'RECEIVING', 'DEVELOPER');

insert into nav_element_mode_role (ELEMENT, NAV_MODE, FOLDER, ROLE)
values ('smr_rec_corrections', '--DEFAULT--', 'RECEIVING', 'INVMGT');

update nav_element_mode n set n.element_mode_name = 'Buyer/Vendor Pack Copy' where element in('smrbuypkcopy');

-----------------------------------------------------------------------------------------------------
-- Inserting into smr_rms_int_type The Interface types 
Prompt Delete from smr_rms_int_type
delete from smr_rms_int_type;

prompt Inserting table smr_rms_int_type...

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (113, 'ALLOC_INTENT', 'Intent to allocate by ASN to WA', 'E');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (100, 'WH_RTV', 'Warehouse RTV''s', 'E');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (101, 'VENDOR_PACKS', 'Extract of Vendor Pakcs', 'E');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (102, 'WH_PO', 'PO extract to WA', 'E');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (103, 'WH_ALLOC', 'Warehouse Allocation', 'E');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (104, 'ALLOC_FULFILL', 'Alloc Fulfillment from WA', 'I');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (105, 'EDI_810', 'Vendor Invoices', 'I');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (106, 'EDI_850_860', 'Po Extract to vendor', 'E');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (107, 'VENDOR_ASN', 'Vendor ASN for WA and Cross Dock PO', 'I');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (108, 'WH_SHIPMENTS', 'Allocation/Transfer Shipments from WA ', 'I');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (109, 'WH_RTW', 'Return to Warehouse', 'E');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (110, 'WH_RECEIPTS', 'Receipts from WA', 'I');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (111, 'WH_ADJUSTMENTS', 'Warehouse Inventory/Receipt Adjustments', 'I');

insert into smr_rms_int_type (INTERFACE_ID, INTERFACE_NAME, DESCRIPTION, INTERFACE_TYPE)
values (112, 'WH_TSF', 'Warehouse Transfers', 'E');


-----------------------------------------------------------------------------------------------------
-- Update  restricted_ind for Xdoc Wh . This is done so that Po receipt has 
-- additional items(Not included as part of PO) or Received_qty > Ordered_qty
-- then such receipts should not be distributed against Xdoc wh and should be received against WH stocked VWH(9522,9532,9542)
update wh set restricted_ind = 'Y' where wh in (9521,9531,9541);

commit;



