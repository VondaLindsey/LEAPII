This script runs in multi threaded fashion. The threads for this job are setup in restart_control
with program_name 'smrEdi810'.

Each thread validates the data that pertains to the thread and writes proper errors in the 
SMR_RMS_INT_ERROR and SMR_IM_EDI_REJECT for reject records if there are any validation errors.

A function is invoked in this script which will generate a file per supplier, multiple files
will be generated so that they all can be loaded concurrently by the base process.