Object Name : SMR_WH_SHIP_SQL

Description:
   The package SMR_WH_SHIP_SQL is used to process the WH Shipments from WA into RMS table.
   The package consists of following Main Functions
   F_INIT_WH_SHIPMENTS - Function used to load data from Interface table into Shipping staging tables
   F_VALIDATE_SHIPMENTS - Function used to validate the Shipping data from WA
   F_PROCESS_WH_SHIPMENTS - Function to load the WH shipment from WA into RMS .
   F_FINISH_PROCESS - Update the status in the Queue Table.	   

Algorithm
   - Call Function F_INIT_WH_SHIPMENTS to load the Staging table SMR_WH_ASN_STAGE from the Interface tables
   - Call function F_VALIDATE_SHIPMENTS to validate the Shipment data from WA . Insert all errors into SMR_RMS_INT_ERROR table.
   - Call function F_LOAD_SHIPMENTS to load Shipment data into RMS
   - Based on the Shipment Type identify if the shipment is for Allocation , Transfer or RTV. Invoke the Base API's based on the shipment type.
   - Call fucntion  F_FINISH_PROCESS to  Update the status in the Interface Queue Table.	   
