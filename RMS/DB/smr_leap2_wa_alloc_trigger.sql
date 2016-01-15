CREATE OR REPLACE TRIGGER SMR_WA_ALLOC
 BEFORE DELETE OR INSERT OR UPDATE
 ON ALLOC_HEADER
REFERENCING NEW AS New OLD AS Old
 FOR EACH ROW
DECLARE


   cursor c_send_wa_alloc is
     select /*+ cardinality(ax 100) cardinality(ad 100) cardinality(ais 100) */   ax.wh_id wh,
           ax.xref_alloc_no alloc_no,
           :New.order_no order_no,
            case when ais.source_type = 1 then
                  'P' 
                when ais.source_type = 2 then
                  'A'
                when ais.source_type = 3 then
                   'W'
           end source,
           dv.division,
           d.dept,
           ail.LOCATION_ID store,
           --ad.to_loc store,
           st.default_wh store_wh,
           sysdate order_date,
           ail.in_store_date date_expected,
          -- ad.in_store_date DATE_EXPECTED,
           ax.item_id item,
           ail.allocated_qty qty,
           :New.status status,
           sysdate create_datetime
      from alc_xref ax,
           alc_item_source ais,
           alc_item_loc ail,
          -- alloc_detail ad,
           item_master im,
           deps d,
           groups g,
           division dv,
           store st
     where ax.alloc_id = ais.alloc_id
       and ail.alloc_id = ais.alloc_id
      -- and ail.item_id = ail.item_id
       and ax.item_id = ail.item_id
       and ax.xref_alloc_no = :New.alloc_no
       and ax.item_id = :New.item
       and ax.wh_id = :New.wh
       and ax.wh_id in (select wh from wh_attributes where wh_type_code = 'PA')
       and ax.item_id = im.item
       and im.dept = d.dept
       and d.group_no = g.group_no
       and g.division = dv.division
       and st.store = ail.LOCATION_ID ;
  
   L_status   alloc_header.status%type;

BEGIN

   for r1 in c_send_wa_alloc loop
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
dbms_output.put_line('STATUS is ' || L_status || ' ' || :New.item || ' ' || :New.item || ' ' || :New.wh );
       if L_status is not null then
           insert into  SMR_RMS_INT_ALLOC_STG (WH, 
                                      ALLOC_NO, 
                                      ORDER_NO, 
                                      SOURCE, 
                                      DIVISION, 
                                      DEPT, 
                                      STORE, 
                                      STORE_WH, 
                                      ORDER_DATE, 
                                      DATE_EXPECTED, 
                                      ITEM, 
                                      QTY, 
                                      STATUS, 
                                      CREATE_DATETIME )
                             values ( r1.WH, 
                                      r1.ALLOC_NO, 
                                      r1.ORDER_NO, 
                                      r1.SOURCE, 
                                      r1.DIVISION, 
                                      r1.DEPT, 
                                      r1.STORE, 
                                      r1.STORE_WH, 
                                      r1.ORDER_DATE, 
                                      r1.DATE_EXPECTED, 
                                      r1.ITEM, 
                                      r1.QTY, 
                                      L_STATUS, 
                                      r1.create_datetime);

       end if;

      

   end loop;
EXCEPTION

  WHEN OTHERS then
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: SMR_WA_ALLOC - Error Inserting into SMR_WA_ALLOC table');

END;
/

