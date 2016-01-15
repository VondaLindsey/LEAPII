Create or replace TRIGGER smr_alc_table_aa_aiur_trg
 AFTER INSERT OR UPDATE OF status ON alc_alloc
  FOR EACH ROW

DECLARE

   L_order_no       alc_item_source.order_no%TYPE;
   L_alloc_id       alc_alloc.alloc_id%TYPE;
   L_new_status     NUMBER(2);
   L_old_status     NUMBER(2);
   L_split_PO_len   NUMBER(2) := SMR_LEAP_INTERFACE_SQL.SPLIT_PO_ORDER_LENGTH;

   CURSOR c_order_no IS
   SELECT order_no
     FROM alc_item_source ais
    WHERE ais.alloc_id = L_alloc_id
      AND ROWNUM = 1;

BEGIN

   L_new_status := to_number(:NEW.status);
   L_old_status := nvl(to_number(:OLD.status),-99);
   L_alloc_id   := :NEW.alloc_id;

   OPEN  c_order_no;
   FETCH c_order_no INTO L_order_no;
   CLOSE c_order_no;

   IF ((L_order_no IS NOT NULL) and (length( L_order_no ) < L_split_PO_len)) THEN

      --Allocation is set to approved status
      IF L_old_status != 2 AND L_new_status = 2 THEN
         INSERT INTO smr_alc_ext (order_no, alloc_id, status, seq_no, action, updated) VALUES (L_order_no, L_alloc_id, L_new_status, SMR_ALC_EXT_SEQ.NEXTVAL, 'R', null);
         SMR_LEAP_INTERFACE_SQL.PROCESS_APPROVED_ALLOC( L_order_no ); /* <-- checks status in above table (smr_alc_ext) not alc_alloc so trigger does not mutate */
--         UPDATE alloc_header set status = 'C' where order_no = L_order_no;
      END IF;

      --Allocation is set to worksheet status
      IF UPDATING and L_new_status = 0 and L_old_status != 0 THEN
         INSERT INTO smr_alc_ext (order_no, alloc_id, status, seq_no, action, updated) VALUES (L_order_no, L_alloc_id, L_new_status, SMR_ALC_EXT_SEQ.NEXTVAL, 'R', null);
      END IF;

      /* OLR V1.01 Delete START
      --Allocation is set deleted.
         IF L_new_status = 7 THEN
            INSERT INTO smr_alc_ext (order_no, alloc_id, status, seq_no, action, updated) VALUES (L_order_no, L_alloc_id, L_new_status, SMR_ALC_EXT_SEQ.NEXTVAL, 'R', null);
         END IF;
      OLR V1.01 Delete END */

   END IF;

EXCEPTION
   WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: smr_alc_table_aa_aiur_trg - '||
                                     ' Allocation '||:NEW.alloc_id||
                                     ' - '||SQLERRM);

END;
/

