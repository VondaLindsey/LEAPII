---   This package will replace current EDI process, this package function call will
--    validate the file, and generates the EDI file from the table. If there is any error
--    in the validation of invoice an error record will be written to INT_ERROR table
--    corresponding invoice will be updated to 'E'

-- Step 1
-- SMR_RMS_INT_EDI_810_HDR_IMP
-- SMR_RMS_INT_EDI_810_DTL_IMP
  Data will be validated from the above tables and will be formatted and writtent to SMR_EDI_810_FINAL_FILE_FORMAT
  table, only if the data passes through validation steps.

-- Step 2
   POST function moves the data to the below HIST tables as below for future reference.
-- SMR_RMS_INT_EDI_810_HDR_HIST
-- SMR_RMS_INT_EDI_810_DTL_HIST
-- SMR_EDI_810_FINAL_FILE_HIST
