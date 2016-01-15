CREATE OR REPLACE FUNCTION RMS13.SMR_ASN_MIN_PACK_QTY (     I_asn               IN     shipment.asn%TYPE,
                                                     I_pack_no           IN     item_master.item%type,
                                                    I_physical_wh          IN     store.store%type ) 
     RETURN VARCHAR2 IS
 
 
 L_item            item_master.item%type;
     L_lowest_qty      item_loc_soh.STOCK_ON_HAND%TYPE := null;
     L_highest_qty      item_loc_soh.STOCK_ON_HAND%TYPE := null;
     L_qty_allocated   item_loc_soh.STOCK_ON_HAND%TYPE :=0;
     L_calc_qty        item_loc_soh.STOCK_ON_HAND%TYPE :=0;

    cursor c_qty is
       select distinct ss.shipment shipment, ss.item item , sum(ss.qty_expected) qty_expected, sum(ss.qty_received) qty_received,
              pb.pack_item_qty
             from shipsku ss, shipment s ,  packitem_breakout pb  where ss.shipment = s.shipment and s.asn= I_asn
               and pb.item = ss.item
               and pb.pack_no = I_pack_no
               and s.to_loc = I_physical_wh
             group by ss.shipment, ss.item, s.shipment, s.asn ,pb.pack_item_qty ;

  
  BEGIN
  
  
     for r1 in c_qty loop
          L_item := r1.item;
          
  
         L_calc_qty := round (( r1.qty_expected - nvl( r1.qty_received,0) )/r1.pack_item_qty, 0);
     
         if ( L_lowest_qty > L_calc_qty or L_lowest_qty is null )then
            L_lowest_qty := L_calc_qty  ;
         end if;
     
      if ( L_highest_qty < L_calc_qty or L_highest_qty is null )then
            L_highest_qty := L_calc_qty  ;
         end if;
     end loop;
     
     
     dbms_output.put_line(' lowest qty is  ' || L_lowest_qty || ' highest qty ' || L_highest_qty);
     
     return (L_lowest_qty || '~' || L_highest_qty);
     end;
/