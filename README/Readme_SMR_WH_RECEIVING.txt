Object Name : SMR_WH_RECEIVING

Description:
   The package SMR_WH_RECEIVING is used to process the WH receipts from WA into RMS.
   The package consists of following Main Functions
   F_INIT_WH_RECEIVING - Function used to load data from Interface table into Receiving staging tables
   F_VALIDATE_RECEIPT - Function used to validate the Receiving data from WA
   F_PROCESS_RECEIPTS - Function to load the WH receipts fro PO and Transfers into RMS  The Functions invokes the base API to   
      process the receipt data.
   F_FINISH_PROCESS - Update the status in the Queue Table.	


Algorithm
   - Call Function F_INIT_WH_RECEIVING to load the Staging table SMR_WH_RECEIVING_DATA from the Interface tables
   - Call function F_VALIDATE_RECEIPT to validate the Adjustment data from WA. Insert all errors into SMR_RMS_INT_ERROR table and      SMR_WH_RECEIVING_ERROR table.
   - Based on the Shipment Type if Reciept is for PO or Transfer Invoke the base API to receive the shipment.
   - For Xdoc PO receipt update the actual_receiving_store in shipsku with the store the carton is intended for.
   - Call fucntion  F_FINISH_PROCESS to  Update the status in the Interface Queue Table.
   