/*-----------------------------------------------------------------------------------------------------------------------
* Module Name:  smr_edi860dl
* Module Description:  re-write for SDQ (Store Delivery Quantity) PO mods to Vendor.
*                      Stein Mart custom extract program to create the SMR PO edi 860 SDQ/ISB table entries.
*                      There is logic in this program that is the same as smr_edi850dl/smr_edi850sdq.
*                      Make sure that updates are done to both programs or any shared
*                      logic is moved to a shared library.
*
* Dependency Notes:    Need to run ordrev to update order revision to latest before running.
*
* Restart Notes:       If program fails in middle of processing PO number, you should be
*                      able to determine po number from restart bookmark and clean file up.
*                      No need to restart after that since will pick up partial process PO
*                      if not updated at end of file writes.  So can remove bookmark and run
*                      from top.
* Change History
* Version Date      Developer       Issue   Description
* ======= ========= =============== ======= =============================================================================
*    1.00 27-Mar-15 S. Fehr                   
*--------------------------------------------------------------------------------------------------------------------------------------------------*/
