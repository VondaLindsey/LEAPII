Object Name : mcitmind.fmb

Description :
	The Base Mass Item Maintenance Form used for updating the Item attributes was modified to include the option to 
mass update the Case Name associated an Item Supplier. The hold back distribution for the Bulk Orders(9401) will be enabled for SDC's 953 and 954
only if the Case name of the Item is "Box(BX)"

Algorithm :
    - Once the Case Name Update option is selected for the Item List, display all valid Suppliers available.
	- Ensure that user selects a valid Supplier and a Valid Case Name
	- When the user Say OK the Case name for all valid Item and supplier belonging to the Item List are updated.
	- In case the Item-supplier relation does exist for ant item in the Item list such records are ignored.


