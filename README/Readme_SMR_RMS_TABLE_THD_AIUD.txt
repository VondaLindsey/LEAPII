Object Name : SMR_RMS_TABLE_THD_AIUD

Description:
  The Trigger SMR_RMS_TABLE_THD_AIUD on TSFHEAD table is used to load all Vendor RTW created in RMS in the  staging table SMR_RMS_RTW_STG. 
  The data from the staging table is then inserted into the Interface table by a batch job.
  
Algorithm :
  - Check is the transfer is from a Store to warehouse and it is in Shipped status
  - Insert the transfer details into SMR_RMS_RTW_STG.  