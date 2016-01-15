Object Name : SMR_VENDOR_ASN_SQL


Description:
   The package SMR_VENDOR_ASN_SQL is used to Process the Vendor ASN from the staging tables Into RMS. If the Vendor ASN is recieved as 
a File the program also inserts into the Interface tables a Copy of the ASN data.
   The package consists of below Main Functions
   F_INIT_VEND_ASN - Used to copy data from interface table to staging tables. In case ASN data is received in Interface table.
   F_LOAD_ASN_INT_TBL - Used to copy data from Staging to table to Interface tables . If ASN is received as File.
   F_VALIDATE_VEND_ASN - Perform Validation on the ASN data received.
   F_LOAD_ASNS - Function used to load the ASN into RMS Shipment tables.
   F_FINISH_PROCESS - Function to update the status in the Interface Queue tables. 

Algorithm
   -- In case data is recieved in file the data is loaded into below Staging tables using Sqlldr
       SMR_856_VENDOR_ASN  
       SMR_856_VENDOR_ORDER
       SMR_856_VENDOR_ITEM
   -- Invoke the function F_INIT_VEND_ASN or F_LOAD_ASN_INT_TBL based on if ASN is received as File Or in Interface tables
   -- Call the function F_VALIDATE_VEND_ASN to validate the ASN data
   -- Call function F_LOAD_ASNS to load all valid ASN into RMS 
   -- Call funtion F_FINISH_PROCESS to update teh status in interface tables.
  