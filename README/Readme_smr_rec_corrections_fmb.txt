Object Name : smr_rec_corrections.fmb

Description :
    The New form smr_rec_corrections is a replica of the existing form smr_944_corrections Form . The form is used to Correct any Type II errors for the Reciept data from WA . The screen can be used to Fix the errored data and process the Reciept into RMS. The screen has been modiefied to accomadate the Leap 2 changes and the remove any hard coding of warehouses.


Algorithm :
    - The screen displays data from SMR_WH_RECEIVING_ERROR table.
    - The WH recieving Data with Type II errors(Not from Source system) are loaded into  SMR_WH_RECEIVING_ERROR along with the Error Message
    - The Data can be Modified/Deleted using the screen .
    - The updated data can then be reprocessed as a receipt into RMS.