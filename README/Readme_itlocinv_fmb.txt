Object Name : itlocinv.fmb

Description :
	 As part of Leap all Xdoc orders will have split Po created for each of the SDC . This could cause the On order 
for the Item to be Computed Wrongly . In order to avoid this all 9401 orders(bulk orders) will not be included in the On Order Computation.

Algorithm :
The Base form "itlocinv" was modified to compute the On Order totals to be based on the "Include on On-Order" flag for the Order.
The forms includes the orders that are flagged to be "Include on On-Order". All 9401 orders after Leap 2 will not be included in 
the On-Order Computation. 

