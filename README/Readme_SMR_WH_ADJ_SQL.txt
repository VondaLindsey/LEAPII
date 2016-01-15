Object Name : SMR_WH_ADJ_SQL

Description:
   The package SMR_WH_ADJ_SQL is used to create Inventory and reciept adjustment from WA into RMS table.
   The package consists of following Main Functions
   F_INIT_WH_ADJ - Function used to load data from Interface table into ASN staging tables
   F_VALIDATE_ADJ - Function used to validate the adjustment data from WA
   F_LOAD_ADJ - Function to load the adjustments into RMS based on the Inventory Status . In case of the Reciept Adustment the 
       adjustments are loaded into staging table in case of any invoice exists for the Order and has been attempted to Match.
   F_FINISH_PROCESS - Update the status in the Interface Queue Table.	   

Algorithm
   - Call Function F_INIT_WH_ADJ to load the Staging table SMR_RMS_ADJ_STAGE from the Interface tables
   - Call function F_VALIDATE_ADJ to validate the Adjustment data from WA . Insert all errors into SMR_RMS_INT_ERROR table.
   - Call function F_LOAD_ADJ to load adjustment data into RMS
   - Based on the adjstment reason code create a Inventory adjusmtent or a Receipt Adjustment in RMS
   - Call fucntion  F_FINISH_PROCESS to  Update the status in the Interface Queue Table.	   
