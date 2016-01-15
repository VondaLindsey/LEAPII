CREATE OR REPLACE PACKAGE RMS13.SMR_RMS_INT_EDI_810  AS

/*=====================================================================================*/
--
-- Module Name: SMR_RMS_INT_EDI_810_PROCESS
-- Description: 
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== ===============================================
-- 1.00    01-May-15 A.Potukuchi          For EDI 810 Process
--
------------------------------------------------------------------------------------
---   This package will replace current EDI process, this package function call will
--    validate the file, and generates the EDI file from the table. If there is any error
--    in the validation of invoice an error record will be written to INT_ERROR table
--    corresponding invoice will be updated to 'E'

--FUNCTION Name: VALIDATE_DATA
--Purpose:       This funtion will validate an invoice address that associated with
--               the given supplier number or a partner ID of a given entity
--              
------------------------------------------------------------------------------------
FUNCTION VALIDATE_DATA(O_error_message          IN OUT VARCHAR2, 
                        I_num_threads            IN     NUMBER,
                        I_thread_val             IN     NUMBER)
   RETURN BOOLEAN;
------------------------------------------------------------------------------------
FUNCTION EDI810_PRE(O_error_message          IN OUT VARCHAR2 )
RETURN BOOLEAN;
------------------------------------------------------------------------------------
FUNCTION EDI810_POST(O_error_message          IN OUT VARCHAR2 )
RETURN BOOLEAN;
------------------------------------------------------------------------------------
END SMR_RMS_INT_EDI_810;
/
