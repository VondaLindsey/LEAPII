Create or replace TRIGGER SMR_860_OH_AIUR
 AFTER INSERT OR UPDATE ON ORDHEAD
 FOR EACH ROW
DECLARE

   L_order_no               ORDHEAD.ORDER_NO%TYPE := :new.order_no;
   L_new_location           ORDHEAD.LOCATION%TYPE := :new.location;
   L_old_location           ORDHEAD.LOCATION%TYPE := :old.location;
   L_dept                   ORDHEAD.DEPT%TYPE     := :new.dept;
   L_extract_850_ind        SMR_ORD_EXTRACT.EXTRACT_850_IND%TYPE := NULL;
   L_extract_850_date       SMR_ORD_EXTRACT.EXTRACT_850_DATE%TYPE := null;
   L_last_extract_rev_no    SMR_ORD_EXTRACT.LAST_EXTRACT_REV_NO%TYPE := null;
   L_extract_850_rel_ind    SMR_ORD_EXTRACT.EXTRACT_850_REL_IND%TYPE := NULL;
   L_resend_850_ind         SMR_ORD_EXTRACT.RESEND_850_IND%TYPE := NULL;
   L_error_message          VARCHAR2(255) := NULL;
   L_split_PO_len           NUMBER(2) := SMR_LEAP_INTERFACE_SQL.SPLIT_PO_ORDER_LENGTH;

   PROGRAM_ERROR   EXCEPTION;

   cursor c_non_alloc_wh(I_wh number) is
   select 'Y'
     from wh,
          wh_attributes wh_a
    where wh.physical_wh = wh_a.wh
      and ups_district = 1
      and wh.wh = I_wh;

   L_non_alloc_wh_old varchar2(1);
   L_non_alloc_wh_new varchar2(1);


BEGIN

      open  c_non_alloc_wh(L_old_location);
      fetch c_non_alloc_wh into L_non_alloc_wh_old;
      close c_non_alloc_wh;

      L_non_alloc_wh_old := nvl(L_non_alloc_wh_old,'N');

      open  c_non_alloc_wh(L_new_location);
      fetch c_non_alloc_wh into L_non_alloc_wh_new;
      close c_non_alloc_wh;

      L_non_alloc_wh_new := nvl(L_non_alloc_wh_new,'N');

      IF INSERTING THEN

         -- if DSW we do not insert status record since do not want in smr edi extract
         if L_dept != 592 then

            -- setup row for SMR extract status where default is No for not extracted
            L_resend_850_ind := NULL;

            -- if stand alone order, will extract like bulk but no release
            if L_non_alloc_wh_new = 'Y' then
               L_extract_850_ind := 'N';
               L_extract_850_rel_ind := NULL;
            -- if not stand alone, then should be release order also
            else
               L_extract_850_ind := 'N';
               L_extract_850_rel_ind := 'N';
            end if;

            if ((length(L_order_no) = L_split_PO_len) and (substr(L_order_no, L_split_PO_len) = 1)) then
            -- new split PO's have already been extracted from bulk
               L_extract_850_ind := 'Y';
               L_extract_850_date := sysdate;
               L_last_extract_rev_no := 0;
            end if;

            INSERT INTO smr_ord_extract (order_no,
                                         extract_850_ind,
                                         extract_850_rel_ind,
                                         extract_850_date,
                                         last_extract_rev_no,
                                         resend_850_ind,
                                         last_update_id,
                                         last_update_datetime)
                                  VALUES (L_order_no,
                                          L_extract_850_ind,
                                          L_extract_850_rel_ind,
                                          L_extract_850_date,
                                          L_last_extract_rev_no,
                                          L_resend_850_ind,
                                          user,
                                          sysdate);
         end if;

      END IF;

      IF UPDATING THEN

         -- if SDC has changed, and has changed to a non null value
         IF NVL(L_new_location,-1) != NVL(L_old_location,-1) AND L_new_location IS NOT NULL THEN

           --if stand alone then should be no release.
           IF L_non_alloc_wh_new = 'Y' THEN

              UPDATE smr_ord_extract
                 SET extract_850_rel_ind = null
               WHERE order_no = L_order_no;

           --if not stand alone then should be a release.
           ELSE

              UPDATE smr_ord_extract
                 SET extract_850_rel_ind = 'N'
               WHERE order_no = L_order_no;

           END IF;

         END IF;

      END IF;

END;
/
