CREATE OR REPLACE TRIGGER SMR_WA_TSF
 BEFORE DELETE OR INSERT OR UPDATE
 ON TSFHEAD
REFERENCING NEW AS New OLD AS Old
 FOR EACH ROW
DECLARE


    cursor c_send_wa_tsf is
    select td.tsf_no,
           td.item,
           td.TSF_QTY qty,
           :New.FROM_LOC FROM_LOC, 
           :New.TO_LOC TO_LOC, 
           :New.INVENTORY_TYPE INVENTORY_TYPE, 
          :New.TSF_TYPE TSF_TYPE,
           dv.division,
          d.dept,
          sysdate order_date,
          :New.EXP_DC_DATE DATE_EXPECTED,
          :New.status status,
          sysdate create_datetime
     from TSFDETAIL td,
          item_master im,
          deps d,
          groups g,
          division dv
    where td.tsf_no = :New.tsf_no
      and td.item = im.item
      and :New.from_loc_type = 'W'
      and im.dept = d.dept
      and d.group_no = g.group_no
      and g.division = dv.division;
  
   L_status   tsfhead.status%type;

BEGIN

   for r1 in c_send_wa_tsf loop
       L_status := null;
       IF INSERTING then
          if :New.status = 'A' and nvl(:Old.status,'X') <> 'A' then
              L_status := 'A';
          end if;
       END IF;
       IF UPDATING then
          if :New.status = 'C' and :Old.status <> 'C' then
              L_status := 'C';
          end if;
          if :New.status = 'A' and :Old.status <> 'A' then
	      L_status := 'A';
          end if;
          if :New.status = 'D' and :Old.status <> 'D' then
	      L_status := 'D';
          end if;
       END IF;
       IF DELETING then
            L_status := 'D';
       END IF;

       if L_status is not null then
           insert into  SMR_RMS_INT_TSF_STG (TSF_NO, 
                                         FROM_LOC, 
                                         TO_LOC, 
                                         INVENTORY_TYPE, 
                                         TSF_TYPE, 
                                         DIVISION, 
                                         DEPT, 
                                         DATE_EXPECTED, 
                                         ITEM, 
                                         QTY, 
                                         STATUS, 
                                         CREATE_DATETIME )
                             values ( r1.TSF_NO, 
                                      r1.FROM_LOC, 
                                      r1.TO_LOC, 
                                      r1.INVENTORY_TYPE, 
                                      r1.TSF_TYPE, 
                                      r1.DIVISION, 
                                      r1.DEPT, 
                                      r1.DATE_EXPECTED, 
                                      r1.ITEM, 
                                      r1.QTY, 
                                       L_STATUS, 
                                       r1.CREATE_DATETIME);

       end if;

      

   end loop;
EXCEPTION

  WHEN OTHERS then
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: SMR_WA_TSF - Error Inserting into SMR_WA_TSF table');

END;
/