-- smr_leap2_wa_send_alloc_tsf.ksh

This shell script will run in UC4 and run part of nightly schedule to send the Allocation/TSF to WA.
There are 2 different functions for each of the process SEND_ALLOC_WA and SEND_TSF_WA.
These 2 functions will run after one another.
Once this information is processed from the staging tables SMR_RMS_INT_ALLOC_STG/SMR_RMS_INT_TSF_STG the data will be deleted.
The data from the able 2 staging tables will be processed into SMR_RMS_INT_ALLOC_TSF_EXP table after generating proper group_id, record_id.