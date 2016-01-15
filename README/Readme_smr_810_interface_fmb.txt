Object Name : smr_810_interface.fmb

Description :
    The New custom screen smr_810_interface is used to display all the PO invoices from Vendor are displayed. The screen displays all the invoices fromt he 810 EDI interface tables . The screen displays all invoices from Vendor. The purpose of the screen is just to give Finance team a idea of all the invoices that are recieved from a Vendor and if they are successfully loaded into REIM.


ALgorithm
    - The Form display data from the EDI interface tables which is loaded from the EDI 810 file recieved .
    - The Invoice Header Details is fetched from SMR_RMS_INT_EDI_810_HDR_IMP.
    - The Invoice Detail records are displayed from SMR_RMS_INT_EDI_810_DTL_HIST.
    - The screen also display if the Invoices is sucessfully loaded into REIM or not.
    - The user can also view any Errors while loading the invoices from the 810 File. The error is displayed from SMR_RMS_INT_ERROR


