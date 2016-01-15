CREATE OR REPLACE PACKAGE BODY "SMR_E3_EXTRACT_SQL" IS
--------------------------------------------------------------------------------
--Program Name : smr_e3_dept_add_sql
--Description  : This script will add items into SMR_STAGING_E3_ITEM and SMR_STAGING
--               _E3_ONHAND by DEPT SCHEDULE in 1st to 9th day fo month.
--               The script will be run nightly. It will be FTPed
--               to E3.
-- Change Log;
-- 05/31/2012  VERSION 1.19 HKIM
--             Changed select primary supplier from item_supp_country instead of
--             item_loc_soh in EXTRACT_CUR and EXTRACT_PACKITEM_CUR on ONHAND_SQL.
--
-- 06/01/2012  VERSION 1.21 HKIM (ONHAND_SQL)
--             Changed made on ITEM_SQL no to process 'D' in action flag but the
--             item exist on UDA_ITEM_LOV with replenishment.
--             added insert into smr_staging_e3_onhand from smr_e3_tran_data
-- 06/04/2012  VERSION 1.22 HKIM (ONHAND_SQL)
--             Changed made on Sales Units calculation that is not summerized
--             when the number is negative
-- 06/07/2012  VERSION 1.23 HKIM (ONHAND_SQL)
--             Changed made on CSR01 select items only SELLABLE = YES
-- 06/08/2012  VERSION 1.24 HKIM
--             Changed made to exclude STYLEs from replenishment (SELLABLE = 'Y')
-- 06/11/2012  VERSION 1.25 HKIM
--             checking only Item level = 2 and sellable_ind = 'Y'
--             remove checking supplier Matrix = 9999 from item_sql
-- 06/12/2012  Commented to check status ('A','R') from smr_staging_e3_alloc_temp
-- 06/15/2012  HKIM
--             when there is no price on item_loc, it gets the price from rpm_item_zone_price
--             made change on master_update cursor on ITEM  --- V.1.28
-- 06/19/2012  HKIM -- requested by Vonda
--             Modified STORE_GROUP to get right five positions with zeros on LOC_LIST
--             Add selection by Item_level =1 and UDA_ID = 2 and UDA_VALUE = 2
--             It should be made change on triggers too
-- 06/20/2012  HKIM -- requested by Vonda
--             If Item is new, it should be inserted into onhand staging table from staging item
-- 06/30/2012  HKIM Back to previous version 0630/2012 Vonda
-- 07/02/2012  HKIM requested by Vonda
--             1) Do not wtite on hand staging table from DEPT_ADD (only write to ITEM staging table)
--             2) Clear on hand staging table at the begining in ONHAND_SQL
--             and run her query that insert into on hand staging table from item_loc and UDA and item master
--             Full refresh on hand table every day
--             3) purge SMR_E3_TRAN_DATA where processed_flag = 'P' and units < 0 with unprocessed in ONHAND_SQL
-- 07/09/2012  HKIM
--             Made change on ONHAND_SQL to get STYLE level items
-- 08/09/2012  HKIM
--             Added remove duplicated records from smr_staging_e3_onhand_selected table in on hand interface
-- 04/03/2013  HKIM
--             Added Checking a condition NVL(QTY_ALLOCATED,0) > NVL(QTY_TRANSFERRED,0) on ALLOC_DETAIL
-- 6/17/2013   RTHIRUVENGADAM
--             Added delete from SMR_E3SXORD_REJ to SMR_E3_DEPT_ADD_SQL function for ME ticket 222515
-- 09/15/2015  Modifed On order computation to include only orders with "Include On Order" flag set.
--             Thi sisdone as part of Leap so that the On Order qty is not duplicated .

--------------------------------------------------------------------------------
PROCEDURE SHO(I_MESSAGE IN VARCHAR2) IS
   L_DEBUG_ON BOOLEAN := TRUE; -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
BEGIN

   IF L_DEBUG_ON THEN
      dbms_output.put_line('DEBUG:'||I_MESSAGE);
   END IF;
END SHO;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION SMR_E3_DEPT_ADD_SQL(O_error_message IN OUT VARCHAR2)
   RETURN BOOLEAN IS
------------------------------------------------------------------------------------
------------------------------------------------------------------------------------
    L_MAX_FETCH           NUMBER(10) := 1000000;
    L_program             VARCHAR2(61) := PACKAGE_NAME || '.SMR_E3_DEPT_ADD_SQL';
--
    W_DAY                 VARCHAR2(2);
    W_MIN                 NUMBER(3) := 0;
    W_MAX                 NUMBER(3) := 0;
    T_SYSDATE             DATE;
--
CURSOR CSR01 IS
SELECT TO_CHAR(TRUNC(SYSDATE), 'DD')
FROM DUAL;
--
CURSOR CSR02 IS
SELECT sysdate from DUAL;
--
CURSOR csr03 is
SELECT im.item
  FROM item_master im,
       uda_item_lov uil
WHERE IM.ITEM = UIL.ITEM
--   AND IM.ITEM_LEVEL = IM.TRAN_LEVEL
   AND im.item_level = 2
   AND im.dept between w_min and w_max
   AND uil.uda_id = 2
   AND UIL.UDA_VALUE = 1
   AND IM.SELLABLE_IND = 'Y';
--------------------------------------------------------------------------------
----- Added item_level =1 and UDA_ID = 2 and UDA_VALUE = 2 condition  06/19/2012
----- back to the previous version -------------6/30/2012--------------------
/*CURSOR CSR03 IS
SELECT DISTINCT IM.ITEM
   FROM ITEM_MASTER IM,
        (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*                DISTINCT ITEM, UDA_ID, UDA_VALUE
           FROM UDA_ITEM_LOV
          WHERE UDA_ID= 2) U
  WHERE IM.ITEM = U.ITEM
    AND IM.DEPT between w_min and w_max
    AND ((IM.ITEM_LEVEL = 2 AND U.UDA_VALUE = 1) OR (IM.ITEM_LEVEL = 1 AND U.UDA_VALUE = 2))
    AND IM.SELLABLE_IND = 'Y'; */
--------------------------------------------------------------------------------
--------------------------------07/02/12----------------------------------------
/*CURSOR CSR04 IS
SELECT  T1.ITEM, T2.LOC
FROM  ITEM_MASTER T1, ITEM_LOC T2, uda_item_lov t3
WHERE T1.ITEM = T2.ITEM
  AND T2.ITEM = T3.ITEM
--  AND T1.ITEM_LEVEL = T1.TRAN_LEVEL
  AND T1.ITEM_LEVEL = 2
  AND T1.DEPT BETWEEN W_MIN AND W_MAX
  AND T3.UDA_ID = 2
  AND T3.UDA_VALUE = 1
  AND T1.SELLABLE_IND = 'Y'; */

--------------------------------------------------------------------------------
-- Added item_level =1 and UDA_ID = 2 and UDA_VALUE = 2 condition  06/19/2012
----- back to the previous version -------------6/30/2012 --------------------
/*CURSOR  CSR04 IS
SELECT DISTINCT IM.ITEM, IL.LOC
FROM    (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*             DISTINCT ITEM, UDA_ID, UDA_VALUE
                 FROM UDA_ITEM_LOV
                WHERE UDA_ID= 2) U,
        ITEM_MASTER IM,
        ITEM_LOC IL
  WHERE U.ITEM = IM.ITEM
    AND IM.DEPT BETWEEN w_min AND w_max
    AND IM.ITEM = IL.ITEM
    AND ((IM.ITEM_LEVEL = 2 AND U.UDA_VALUE = 1) OR (IM.ITEM_LEVEL = 1 AND U.UDA_VALUE = 2))
    AND IM.SELLABLE_IND = 'Y'; */
--
TYPE TblWorkId IS TABLE OF VARCHAR2 (200);
t_item               TblWorkId := TblWorkId ();
t_loc                TblWorkId := TblWorkId ();
--
BEGIN
-- Added delete from SMR_E3SXORD_REJ to SMR_E3_DEPT_ADD_SQL function for ME ticket 222515 by Raj T
delete from SMR_E3SXORD_REJ;
commit;
-- End

/* -------------------------------------------------------------------- */
/* Add items from item_master to SMR_STAGING_E3_ITEM by dept schedule   */
/* -------------------------------------------------------------------- */
OPEN CSR01;
FETCH CSR01 INTO W_DAY;
CLOSE CSR01;

--w_day := '01';

CASE WHEN W_DAY = '01' THEN w_min := 000; w_max := 199;
     WHEN W_DAY = '02' THEN w_min := 200; w_max := 299;
     WHEN W_DAY = '03' THEN w_min := 300; w_max := 399;
     WHEN W_DAY = '04' THEN w_min := 400; w_max := 499;
     WHEN W_DAY = '05' THEN w_min := 500; w_max := 599;
     WHEN W_DAY = '06' THEN w_min := 600; w_max := 699;
     WHEN W_DAY = '07' THEN w_min := 700; w_max := 799;
     WHEN W_DAY = '08' THEN w_min := 800; w_max := 899;
     WHEN W_DAY = '09' THEN w_min := 900; w_max := 999;
     ELSE null;
END CASE;

OPEN CSR02;
FETCH CSR02 INTO T_SYSDATE;
CLOSE CSR02;

OPEN CSR03;
LOOP FETCH CSR03 BULK COLLECT INTO t_item LIMIT L_MAX_FETCH;
EXIT WHEN t_item.count = 0;
--
FORALL I IN 1..T_ITEM.COUNT
INSERT INTO SMR_STAGING_E3_ITEM
VALUES(t_item (I), 'C', T_SYSDATE);
END LOOP;
--
CLOSE CSR03;
COMMIT;
--------------------------------07/02/12----------------------------------------
/*OPEN CSR04;
LOOP FETCH CSR04 BULK COLLECT INTO t_item, t_loc LIMIT L_MAX_FETCH;
EXIT WHEN t_item.count = 0;
--
FORALL I IN 1..T_ITEM.COUNT
INSERT INTO SMR_STAGING_E3_ONHAND
VALUES(t_item (I), t_loc(I), 'C', T_SYSDATE);
END LOOP;
--
CLOSE CSR04;
--------------------------------------------------------------------------------
COMMIT; */
--------------------------------------------------------------------------------
RETURN TRUE;

EXCEPTION
    when UTL_FILE.INVALID_OPERATION then
       O_error_message := sql_lib.create_msg ('SMR_E3_OPERATION',
                                              L_PROGRAM);
      RETURN FALSE;
    when OTHERS then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR',
                                               SQLERRM,
                                               'SMR_E3_DEPT_ADD');
      RETURN FALSE;
END SMR_E3_DEPT_ADD_SQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION SMR_E3_STORE_SQL(O_error_message IN OUT VARCHAR2)
   RETURN BOOLEAN IS
--------------------------------------------------------------------------------
--Program Name : smr_E3_store_sql
--Description  : This script will populate SMR_E3 for STORE interface
--               from RMS to E3 on iSeries.
--------------------------------------------------------------------------------
    L_program             VARCHAR2(61)   := PACKAGE_NAME || '.SMR_E3_STORE_SQL';
    L_MAX_FETCH           NUMBER (10) := 100000;
    I                     NUMBER(10) := 0;
    L_timestamp           VARCHAR2(17) :=
                          to_char(systimestamp,'YYYYMMDDHH24MISS');
    L_extract_filename    VARCHAR2(4000);
    L_line                VARCHAR2(3000);
    g_linesize            NUMBER(4) := 3000;
    L_operation           VARCHAR2(2000) :=
                          'UTL_FILE.FOPEN with logical path '||'MMOUT';
    l_path                VARCHAR2(5) := 'MMOUT';
    t_xloc                NUMBER(10);
    t_xflag               VARCHAR2(1);
    t_xdate               VARCHAR2(20);
    T_ITEM                VARCHAR2(25);
    T_SUPPLIER            NUMBER(10);
--------------------------------------------------------------------------------
CURSOR CSR01 IS
SELECT  LOC, ACTION_FLAG, to_char(UPDTME,'DD-MM-YYYY HH24:MM:SS')
  FROM  SMR_STAGING_E3_STORE;
--------------------------------------------------------------------------------
CURSOR  CSR02 IS
SELECT b.loc, c.action_flag
    FROM (SELECT loc, MAX(updtme) xtime
          FROM smr_staging_e3_store_temp
        GROUP BY loc) b,
      smr_staging_e3_store_temp c
 WHERE b.loc = c.loc
 and b.xtime = c.updtme;
--------------------------------------------------------------------------------
TYPE TblWorkId IS TABLE OF VARCHAR2 (200);
t_loc                TblWorkId := TblWorkId ();
t_flag               TblWorkId := TblWorkId ();
--------------------------------------------------------------------------------
CURSOR CHANGE_CURSOR IS
SELECT 'E3T'||' '||to_char(lpad(t1.store,5,0))||
       rpad(substr(t1.store_name,1,30),30,' ')||
       '                              '||
       '                              '||
       '                    '||'  '||'         '||
       '                              '||
       '                              '||
       '                              '||'  '||'         '||
       nvl(substr(t1.phone_number,2,3),'000')||
       nvl(substr(t1.phone_number,7,3),'000')||nvl(substr(t1.phone_number,11,4),'0000')||
       rpad(to_char(t1.district),5,' ')||
       nvl(t1.store_class,' ')||
       '     '||
       '                              '||
       '                                        '||
       '                     '||
       '                          '||
       'C' output_line
  FROM STORE t1,SMR_STAGING_E3_STORE_SELECTED t2
 WHERE t1.store = t2.loc
   AND t2.loc < 800
   AND upper(t2.action_flag) = 'C'
   AND nvl(t1.store_close_date,get_vdate+1) > get_vdate;
--------------------------------------------------------------------------------
CURSOR DELETE_CURSOR IS
SELECT 'E3T'||'NONE '||to_char(lpad(t1.store,5,0))||
       rpad(substr(t1.store_name,1,30),30,' ')||
       '                              '||
       '                              '||
       '                    '||'  '||'         '||
       '                              '||
       '                              '||
       '                              '||'  '||'         '||
       nvl(substr(t1.phone_number,2,3),'000')||
       nvl(substr(t1.phone_number,7,3),'000')||nvl(substr(t1.phone_number,11,4),'0000')||
       rpad(to_char(t1.district),5,' ')||
       nvl(t1.store_class,' ')||
       '     '||
       '                              '||
       '                                        '||
       '                     '||
       '                          '||
       'D' output_line
  FROM STORE t1,SMR_STAGING_E3_STORE_SELECTED t2
 WHERE t1.store = t2.loc
   AND t2.loc < 800
   AND upper(t2.action_flag) = 'D'
   AND nvl(t1.store_close_date,get_vdate+1) > get_vdate;
--------------------------------------------------------------------------------
CURSOR NEW_CURSOR IS
SELECT 'E3T'||'NONE '||to_char(lpad(t1.store,5,0))||
       rpad(substr(t1.store_name,1,30),30,' ')||
       '                              '||
       '                              '||
       '                    '||'  '||'         '||
       '                              '||
       '                              '||
       '                              '||'  '||'         '||
       nvl(substr(t1.phone_number,2,3),'000')||
       nvl(substr(t1.phone_number,7,3),'000')||nvl(substr(t1.phone_number,11,4),'0000')||
       rpad(to_char(t1.district),5,' ')||
       nvl(t1.store_class,' ')||
       '     '||
       '                              '||
       '                                        '||
       '                     '||
       '                          '||
       'N' output_line
  FROM STORE t1,SMR_STAGING_E3_STORE_SELECTED t2
 WHERE t1.store = t2.loc
   AND t2.loc < 800
   AND upper(t2.action_flag) = 'N'
   AND nvl(t1.store_close_date,get_vdate+1) > get_vdate;
-------------------------------------------------------------------------------
-- INSERT RECORD TO E3_ITEM WHEN IT HAS NEW STORE
--------------------------------------------------------------------------------
CURSOR CSR_INSERT_ITEM IS
SELECT T2.ITEM
  FROM SMR_STAGING_E3_STORE_SELECTED T1, ITEM_LOC T2, Item_master t3, UDA_ITEM_LOV T4
 WHERE T1.LOC = T2.LOC
   AND upper(T1.ACTION_FLAG) = 'N'
   AND T2.ITEM = T3.ITEM
--   AND T3.ITEM_LEVEL = T3.TRAN_LEVEL
   AND T3.ITEM_LEVEL = 2
   AND T3.ITEM = T4.ITEM
   AND t4.uda_id = 2
   AND T4.UDA_VALUE =1
   AND T3.SELLABLE_IND = 'Y';
--------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Added item_level =1 and UDA_ID = 2 and UDA_VALUE = 2 condition  06/19/2012
----- back to the previous version -------------6/30/2012 --------------------
/*CURSOR CSR_INSERT_ITEM IS
SELECT T2.ITEM
  FROM SMR_STAGING_E3_STORE_SELECTED T1,
       ITEM_LOC T2,
       ITEM_MASTER T3,
       (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*             DISTINCT ITEM, UDA_ID, UDA_VALUE
                 FROM UDA_ITEM_LOV
                WHERE UDA_ID= 2) T4
 WHERE T1.LOC = T2.LOC
   AND upper(T1.ACTION_FLAG) = 'N'
   AND T2.ITEM = T3.ITEM
   AND t3.item = t4.item
   AND ((T3.ITEM_LEVEL = 2 AND T4.UDA_VALUE = 1) OR (T3.ITEM_LEVEL = 1 AND T4.UDA_VALUE = 2))
   AND T3.SELLABLE_IND = 'Y'; */

--------------------------------------------------------------------------------
-- INSERT RECORD TO E3_SUPP WHEN IT HAS NEW STORE
--------------------------------------------------------------------------------
CURSOR CSR_INSERT_SUPPLIER IS
SELECT distinct T3.SUPPLIER
  FROM SMR_STAGING_E3_STORE_SELECTED T1,
       ITEM_LOC T2,
       ITEM_SUPPLIER T3,
       ITEM_MASTER T4,
       UDA_ITEM_LOV T5
 WHERE T1.LOC = T2.LOC
   AND upper(T1.ACTION_FLAG) = 'N'
   AND UPPER(T3.PRIMARY_SUPP_IND) = 'Y'
   AND T2.ITEM = T3.ITEM
   AND T3.ITEM = T4.ITEM
--   AND T4.ITEM_LEVEL = T4.TRAN_LEVEL
   AND T4.ITEM_LEVEL = 2
   AND T4.ITEM = T5.ITEM
   AND T5.UDA_ID = 2
   AND T5.UDA_VALUE =1
   AND T4.SELLABLE_IND = 'Y';

--------------------------------------------------------------------------------
-- Added item_level =1 and UDA_ID = 2 and UDA_VALUE = 2 condition  06/19/2012
----- back to the previous version -------------6/30/2012 --------------------
/*CURSOR CSR_INSERT_SUPPLIER IS
SELECT distinct T3.SUPPLIER
  FROM SMR_STAGING_E3_STORE_SELECTED T1,
       ITEM_LOC T2,
       ITEM_SUPPLIER T3,
       ITEM_MASTER T4,
       (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*             DISTINCT ITEM, UDA_ID, UDA_VALUE
                 FROM UDA_ITEM_LOV
                WHERE UDA_ID= 2) T5
 WHERE T1.LOC = T2.LOC
   AND upper(T1.ACTION_FLAG) = 'N'
   AND UPPER(T3.PRIMARY_SUPP_IND) = 'Y'
   AND T2.ITEM = T3.ITEM
   AND T3.ITEM = T4.ITEM
   AND T4.ITEM = T5.ITEM
   AND ((T4.ITEM_LEVEL = 2 AND T5.UDA_VALUE = 1) OR (T4.ITEM_LEVEL = 1 AND T5.UDA_VALUE = 2))
   AND T4.SELLABLE_IND = 'Y';   */

--------------------------------------------------------------------------------
L_extract_file  UTL_FILE.FILE_TYPE;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
BEGIN
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'create TABLE BACKUP_SMR_STAGING_E3_STORE as select * from SMR_STAGING_E3_STORE';
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_STORE_TEMP';
--------------------------------------------------------------------------------
open csr01;
loop
fetch csr01 into t_xloc, t_xflag, t_xdate;
exit when csr01%notfound;
insert into smr_staging_e3_store_temp
values (t_xloc, t_xflag, t_xdate);
end loop;
close csr01;
commit;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_STORE_SELECTED';
--------------------------------------------------------------------------------
OPEN CSR02;
LOOP FETCH CSR02 BULK COLLECT INTO t_loc, t_flag LIMIT L_MAX_FETCH;
EXIT WHEN t_loc.count = 0;
FORALL I IN 1..T_LOC.COUNT
INSERT INTO SMR_STAGING_E3_STORE_SELECTED
VALUES(t_loc (I), t_flag (I));
END LOOP;
CLOSE CSR02;
commit;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_STORE';
--------------------------------------------------------------------------------
L_extract_filename := 'SMR_E3_STORE'||'.'||l_timestamp||'.dat';
L_extract_file := UTL_FILE.FOPEN(l_path,
                                 L_extract_filename,
                                 'w',
                                 g_linesize);
FOR ext_out in change_cursor loop
       L_line := ext_out.output_line;
       UTL_FILE.PUT_LINE(L_extract_file,
                         L_line);
END LOOP;
commit;
--------------------------------------------------------------------------------
FOR ext_out in delete_cursor loop
       L_line := ext_out.output_line;
       UTL_FILE.PUT_LINE(L_extract_file,
                         L_line);
END LOOP;
--------------------------------------------------------------------------------
FOR ext_out in new_cursor loop
       L_line := ext_out.output_line;
       UTL_FILE.PUT_LINE(L_extract_file,
                         L_line);
END LOOP;
commit;
--------------------------------------------------------------------------------
   UTL_FILE.FCLOSE(L_extract_file);
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'drop TABLE BACKUP_SMR_STAGING_E3_STORE';
--------------------------------------------------------------------------------
COMMIT;
--------------------------------------------------------------------------------
-- Insert Item record to E3_ITEM
--------------------------------------------------------------------------------
open csr_insert_item;
loop fetch csr_insert_item into t_item;
exit when csr_insert_item%notfound;
insert into smr_staging_e3_item
values (t_item, 'C', sysdate);
end loop;
close csr_insert_item;
commit;
--------------------------------------------------------------------------------
-- Insert Item record to E3_SUPPLIER
--------------------------------------------------------------------------------
open csr_insert_supplier;
loop fetch csr_insert_supplier into t_supplier;
exit when csr_insert_supplier%notfound;
insert into smr_staging_e3_supp
values (t_supplier, 'C', sysdate);
end loop;
close csr_insert_supplier;
commit;
--------------------------------------------------------------------------------
RETURN TRUE;
--------------------------------------------------------------------------------
EXCEPTION
    when UTL_FILE.INVALID_OPERATION then
       O_error_message := sql_lib.create_msg ('SMR_E3_OPERATION',
                                              L_extract_filename,
                                              L_operation);
       RETURN FALSE;
    when UTL_FILE.INVALID_PATH then
         O_error_message := sql_lib.create_msg ('SMR_E3_PATH',
                                              l_path,
                                              L_extract_filename);
        RETURN FALSE;
    when OTHERS then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR',
                                               SQLERRM,
                                              'SMR_E3_STORE');
    RETURN FALSE;
END SMR_E3_STORE_SQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION SMR_E3_SUPP_SQL(O_error_message IN OUT VARCHAR2)
   RETURN BOOLEAN IS
--------------------------------------------------------------------------------
--Program Name : smr_E3_supp_sql
--Description  : This script will populate SMR_E3 for SUPPLIER interface
--               from RMS to E3 on iSeries.
--------------------------------------------------------------------------------
    L_program             VARCHAR2(61)   := PACKAGE_NAME || '.SMR_E3_SUPP_SQL';
    L_MAX_FETCH           NUMBER (10) := 100000;
    I                     NUMBER(10) := 0;
    L_timestamp           VARCHAR2(17) :=
                          to_char(systimestamp,'YYYYMMDDHH24MISS');
    L_extract_filename    VARCHAR2(4000);
    L_line                VARCHAR2(3000);
    g_linesize            NUMBER(4) := 3000;
    L_operation           VARCHAR2(2000) :=
                          'UTL_FILE.FOPEN with logical path '||'MMOUT';
    l_path                VARCHAR2(5) := 'MMOUT';
    l_store               NUMBER(10);
    t_store               VARCHAR2(5);
    l_store_COUNT         NUMBER(10);
    l_SUPP_COUNT          NUMBER(10);
    L_SUPP_STORE_COUNT    NUMBER(20);
    k_supplier            NUMBER(20);
    k_flag                VARCHAR2(200);
    output_line           VARCHAR2(3000);
    t_xsupp               NUMBER(10);
    t_xflag               VARCHAR2(1);
    t_xdate               VARCHAR2(20);
    t_item                VARCHAR2(25);
--------------------------------------------------------------------------------
CURSOR CSR01 IS
SELECT  distinct SUPPLIER, ACTION_FLAG, to_char(UPDTME,'DD-MM-YYYY HH24:MM:SS')
FROM SMR_STAGING_E3_SUPP;
--------------------------------------------------------------------------------
/*CURSOR  CSR02 IS
SELECT B.SUPPLIER, C.ACTION_FLAG
    FROM (SELECT supplier, MAX(updtme) xtime
          FROM smr_staging_e3_supp_temp
        GROUP BY supplier) b,
      smr_staging_e3_supp_temp c
 WHERE b.supplier = c.supplier
 and b.xtime = c.updtme; */

CURSOR  CSR02 IS
SELECT XA.SUPPLIER, XA.ACTION_FLAG, MAX(XA.UPDTME)
    FROM (SELECT UNIQUE SUPPLIER XBSUPP
          FROM SMR_STAGING_E3_SUPP_TEMP) XB,
          SMR_STAGING_E3_SUPP_TEMP XA
 WHERE XB.XBSUPP = XA.SUPPLIER
 group by XA.supplier, XA.action_flag;

--------------------------------------------------------------------------------
TYPE TblWorkId IS TABLE OF VARCHAR2 (200);
T_SUPP               TBLWORKID := TBLWORKID ();
T_FLAG               TBLWORKID := TBLWORKID ();
t_updtme             TblWorkId := TblWorkId ();
--------------------------------------------------------------------------------
CURSOR CSR03 IS
SELECT T2.ITEM
  FROM SMR_STAGING_E3_SUPP_SELECTED T1, ITEM_SUPPLIER T2, Item_master t3, UDA_ITEM_LOV T4
 WHERE T1.SUPPLIER = T2.SUPPLIER
   AND UPPER(T1.ACTION_FLAG) = 'N'   AND T2.ITEM = T3.ITEM
--   AND T3.ITEM_LEVEL = T3.TRAN_LEVEL
   AND T3.ITEM_LEVEL = 2
   AND T3.ITEM = T4.ITEM
   AND t4.uda_id = 2
   AND T4.UDA_VALUE =1
   AND T3.SELLABLE_IND = 'Y';

-----------------------------------------------06/19/2012-----------------------
----- back to the previous version -------------6/30/2012 --------------------
/*CURSOR CSR03 IS
SELECT T2.ITEM
  FROM SMR_STAGING_E3_SUPP_SELECTED T1,
       ITEM_SUPPLIER T2,
       ITEM_MASTER T3,
       (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*             DISTINCT ITEM, UDA_ID, UDA_VALUE
                 FROM UDA_ITEM_LOV
                WHERE UDA_ID= 2) T4
 WHERE T1.SUPPLIER = T2.SUPPLIER
   AND UPPER(T1.ACTION_FLAG) = 'N'
   AND T2.ITEM = T3.ITEM
   AND T3.ITEM = T4.ITEM
   AND ((T3.ITEM_LEVEL = 2 AND T4.UDA_VALUE = 1) OR (T3.ITEM_LEVEL = 1 AND T4.UDA_VALUE = 2))
   AND T3.SELLABLE_IND = 'Y';  */
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
CURSOR  SUPP_SELECTED IS
SELECT  SUPPLIER,
        ACTION_FLAG
FROM SMR_STAGING_E3_SUPP_SELECTED;
--------------------------------------------------------------------------------
CURSOR STORE_COUNT IS
SELECT COUNT(*)
FROM STORE
WHERE STORE < 900;
--AND nvl(store_close_date,get_vdate+1) > get_vdate;
--------------------------------------------------------------------------------
CURSOR SUPP_COUNT IS
SELECT COUNT(*)
FROM SMR_STAGING_E3_SUPP_SELECTED;
--------------------------------------------------------------------------------
CURSOR STORE_CUR IS
SELECT STORE FROM STORE WHERE STORE < 900
--AND nvl(store_close_date,get_vdate+1) > get_vdate
ORDER BY STORE;
--------------------------------------------------------------------------------
CURSOR SUPP_STORE_COUNT IS
SELECT COUNT(*)
FROM SMR_STAGING_E3_SUPP_STORE;
--------------------------------------------------------------------------------
CURSOR UPDATE_CLOSED_STORE IS
SELECT STORE FROM STORE WHERE STORE < 900
AND store_close_date < get_vdate + 1
ORDER BY STORE;
--------------------------------------------------------------------------------
CURSOR CHANGE_SUPP IS
SELECT 'E3T'||
       'NONE '||
       'V'||
       TO_CHAR(LPAD(T1.STORE,5,0))||
       '     '||
       TO_CHAR(LPAD(T1.SUPPLIER,8,0))||
       '     '||
       '                                                                              '||
       RPAD(T2.SUP_NAME,30,' ')||
       lpad(1,3,0)||
       LPAD(0,7,0)||
       LPAD(0,7,0)||
       ' '||
--       DECODE(T1.ACTION_FLAG,'D',T1.ACTION_FLAG,' ') OUTPUT_LINE
       t1.action_flag output_line
  FROM SMR_STAGING_E3_SUPP_STORE t1, sups t2
 WHERE t1.supplier = t2.supplier
 ORDER BY T1.SUPPLIER, T1.STORE;
--------------------------------------------------------------------------------
L_extract_file  UTL_FILE.FILE_TYPE;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
BEGIN
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'create TABLE BACKUP_SMR_STAGING_E3_SUPP as select * from SMR_STAGING_E3_SUPP';
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_SUPP_TEMP';

COMMIT;
--------------------------------------------------------------------------------
open csr01;
LOOP
fetch csr01 into t_xsupp, t_xflag, t_xdate;
exit when csr01%notfound;
insert into smr_staging_e3_supp_temp
values (t_xsupp, t_xflag, t_xdate);
end loop;
close csr01;

COMMIT;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_SUPP';
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_SUPP_SELECTED';
COMMIT;
--------------------------------------------------------------------------------
OPEN CSR02;
LOOP
FETCH CSR02 BULK COLLECT INTO t_supp, t_flag, T_UPDTME LIMIT L_MAX_FETCH;
EXIT WHEN t_supp.count = 0;
FORALL I IN 1..T_SUPP.COUNT
INSERT INTO SMR_STAGING_E3_SUPP_SELECTED
VALUES(t_supp (I), t_flag (I));
END LOOP;
CLOSE CSR02;
COMMIT;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_SUPP_STORE';
COMMIT;
--------------------------------------------------------------------------------
OPEN STORE_COUNT;
FETCH STORE_COUNT INTO L_STORE_COUNT;
CLOSE STORE_COUNT;
--------------------------------------------------------------------------------
OPEN SUPP_COUNT;
FETCH SUPP_COUNT INTO L_SUPP_COUNT;
CLOSE SUPP_COUNT;
--------------------------------------------------------------------------------
OPEN SUPP_SELECTED;
FOR IPX IN 1..L_SUPP_COUNT LOOP
FETCH SUPP_SELECTED INTO k_supplier, k_flag;
-----------------------------
    OPEN store_cur;
    FOR IDX IN 1..l_store_count LOOP
    FETCH STORE_CUR into l_store;
    INSERT INTO smr_staging_e3_supp_store
    VALUES (k_supplier, l_store, k_flag);
    END LOOP;
    CLOSE store_cur;
END LOOP;
CLOSE SUPP_SELECTED;
COMMIT;

-----------------------------
FOR RECS IN update_closed_store
  LOOP
  UPDATE SMR_STAGING_E3_SUPP_STORE
     SET ACTION_FLAG = 'D'
   WHERE STORE = RECS.STORE;
  END LOOP;

  COMMIT;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
L_extract_filename := 'SMR_E3_SUPP'||'.'||l_timestamp||'.dat';
L_extract_file := UTL_FILE.FOPEN(l_path,
                                 L_extract_filename,
                                 'w',
                                 g_linesize);
OPEN SUPP_STORE_COUNT;
FETCH SUPP_STORE_COUNT INTO L_SUPP_STORE_COUNT;
CLOSE SUPP_STORE_COUNT;
--------------------------------------------------------------------------------
OPEN CHANGE_SUPP;
FOR IKX IN 1..L_SUPP_STORE_COUNT LOOP
FETCH CHANGE_SUPP INTO OUTPUT_LINE;
L_line := output_line;
UTL_FILE.PUT_LINE(L_extract_file, L_line);
END LOOP;
CLOSE CHANGE_SUPP;
UTL_FILE.FCLOSE(L_extract_file);
COMMIT;
--------------------------------------------------------------------------------
OPEN CSR03;
LOOP
FETCH CSR03 INTO T_ITEM;
EXIT WHEN CSR03%NOTFOUND;
INSERT INTO SMR_STAGING_E3_ITEM
VALUES (T_ITEM, 'C', SYSDATE);
END LOOP;
CLOSE CSR03;

COMMIT;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'drop TABLE BACKUP_SMR_STAGING_E3_SUPP';
--------------------------------------------------------------------------------
COMMIT;
--------------------------------------------------------------------------------
RETURN TRUE;
--------------------------------------------------------------------------------
EXCEPTION
    when UTL_FILE.INVALID_OPERATION then
       O_error_message := sql_lib.create_msg ('SMR_E3_OPERATION',
                                              L_extract_filename,
                                              L_operation);
      RETURN FALSE;
    when UTL_FILE.INVALID_PATH then
         O_error_message := sql_lib.create_msg ('SMR_E3_PATH',
                                              l_path,
                                              L_extract_filename);
        RETURN FALSE;
    when OTHERS then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR',
                                               SQLERRM,
                                              'SMR_E3_SUPPLIER');
    RETURN FALSE;
END SMR_E3_SUPP_SQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION SMR_E3_ITEM_SQL(O_error_message IN OUT VARCHAR2)
   RETURN BOOLEAN IS
------------------------------------------------------------------------------------
--Program Name : smr_e3_item_sql
--Description  : This script will populate SMR_E3_ITEM for E3 interface.
--               The script will be run Nightly. It will be FTPed
--               to E3.
------------------------------------------------------------------------------------
    L_program             VARCHAR2(61)   := PACKAGE_NAME || '.SMR_E3_ITEM_SQL';
    L_MAX_FETCH           NUMBER (10) := 100000;
    L_timestamp           VARCHAR2(17) :=
                          to_char(systimestamp,'YYYYMMDDHH24MISS');
    L_extract_filename    VARCHAR2(4000);
    L_line                VARCHAR2(3000);
    g_linesize            NUMBER(4) := 3000;
    L_operation           VARCHAR2(2000) :=
                          'UTL_FILE.FOPEN with logical path '||'MMOUT';
    l_path                VARCHAR2(5) := 'MMOUT';
    L_ITEM_STORE_COUNT    NUMBER(10) := 0;
    l_item                VARCHAR2(20);
    l_store               VARCHAR2(5);
    l_flag                VARCHAR2(1);
    output_line           VARCHAR2(3000);
    t_xitem               VARCHAR2(25);
    t_xflag               VARCHAR2(1);
    t_xdate               VARCHAR2(20);
--------------------------------------------------------------------------------
-----added check only SKU level item-----------------V1.24--- 6/8/2012----------
CURSOR CSR01 IS
SELECT DISTINCT T1.ITEM, T1.ACTION_FLAG, T1.UPDTME
--TO_CHAR(t1.UPDTME,'DD-MM-YYYY HH24:MM:SS')
  FROM SMR_STAGING_E3_ITEM T1,
       ITEM_MASTER T2
WHERE T1.ITEM = T2.ITEM
  AND T2.ITEM_LEVEL = 2
  AND T2.SELLABLE_IND = 'Y';

 --t1.item in (SELECT isp.item   --- it is commented 6/11/2012
      --            FROM item_supplier isp,
      --                 sup_traits_matrix stm
      --           WHERE isp.supplier = stm.supplier
      --             AND STM.SUP_TRAIT = 9999)
--  AND
--  AND T2.ITEM_LEVEL = T2.TRAN_LEVEL
--------------------------------------------------------------------------------
-----added check only SKU level item-------------------- 6/19/2012--------------
/*CURSOR CSR01 IS
SELECT DISTINCT t1.ITEM, t1.ACTION_FLAG, TO_CHAR(t1.UPDTME,'DD-MM-YYYY HH24:MM:SS')
  FROM SMR_STAGING_E3_ITEM T1,
       ITEM_MASTER T2
WHERE T1.ITEM = T2.ITEM
  AND (T2.ITEM_LEVEL in (1, 2))
  AND T2.SELLABLE_IND = 'Y';
----- back to the previous version -------------6/30/2012 --------------------
/* CURSOR CSR01 IS
--  SELECT DISTINCT T1.ITEM, T1.ACTION_FLAG, TO_CHAR(T1.UPDTME,'DD-MM-YYYY HH24:MM:SS')
    SELECT DISTINCT T1.ITEM, T1.ACTION_FLAG, T1.UPDTME
    FROM SMR_STAGING_E3_ITEM T1,
         (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*            DISTINCT ITEM, UDA_ID, UDA_VALUE
                FROM UDA_ITEM_LOV
               WHERE UDA_ID= 2) UIL,
          ITEM_MASTER IM
  WHERE T1.ITEM =  UIL.ITEM
    AND UIL.ITEM = IM.ITEM
    AND ((IM.ITEM_LEVEL = 2 AND UIL.UDA_VALUE = 1) OR (IM.ITEM_LEVEL = 1 AND UIL.UDA_VALUE = 2))
    AND IM.SELLABLE_IND = 'Y'
    AND IM.STATUS = 'A'; */

--------------------------------------------------------------------------------
CURSOR  CSR02 IS
SELECT distinct b.item, c.action_flag
    FROM (SELECT item, MAX(updtme) xtime
          FROM smr_staging_e3_item_temp
        GROUP BY ITEM) B,
      SMR_STAGING_E3_ITEM_TEMP C
 WHERE B.ITEM = C.ITEM
  AND B.XTIME = C.UPDTME;
--------------------------------------------------------------------------------
TYPE TblWorkId IS TABLE OF VARCHAR2 (200);
t_item               TblWorkId := TblWorkId ();
t_flag               TblWorkId := TblWorkId ();
t_updtme             TblWorkId := TblWorkId ();
--------------------------------------------------------------------------------
cursor item_store is
select t1.item, t2.store, t1.action_flag
  from smr_staging_e3_item_selected t1,
       STORE T2
WHERE --nvl(t2.store_close_date,get_vdate+1) > get_vdate
  --AND
  t2.store < 900
order by t1.item, t2.store;
 --------------------------------------------------------------------------------
cursor upc_update is
select t1.rowid, t1.item itema, t1.store storea, t2.item itemb, t1.action_flag flag
from smr_staging_e3_item_store t1, item_master t2
where t1.item = t2.item_parent
and t2.item_number_type in ('UPC-A', 'EAN13', 'ISBN13');
--------------------------------------------------------------------------------
--cursor supplier_update is
--select t1.rowid, t2.primary_supp psupp, t2.av_cost avcost
--  from smr_staging_e3_item_store t1,
--       item_loc_soh t2
--where t1.item = t2.item
--   and t1.store = t2.loc;
-- 8/1/11
cursor supplier_update is
select t1.rowid, iss.supplier psupp, isc.unit_cost uncost, isc.supp_pack_size spz
  from smr_staging_e3_item_store t1,
       item_supplier iss,
       item_supp_country isc
where t1.item = iss.item
   and upper(iss.primary_supp_ind) = 'Y'
   and iss.item = isc.item
   and iss.supplier = isc.supplier
   and isc.PRIMARY_COUNTRY_IND = 'Y';
--------------------------------------------------------------------------------
cursor retail_update is
select t1.rowid, t2.selling_unit_retail sur
from smr_staging_e3_item_store t1, item_loc t2
where t1.item = t2.item
and t1.store = t2.loc;
--------------------------------------------------------------------------------
cursor master_update is
select t1.rowid,
       nvl(t2.package_size,1) pkgsz,
       substr(t2.item_desc,1,35) itemdesc,
       t2.standard_uom stuom,
       nvl(t2.diff_1,' ') clr,
       NVL(T2.DIFF_2,' ') SZE,
--     nvl(t2.original_retail,0) orgretl,  ---- 06/14/2012
       (select standard_retail from rpm_item_zone_price where item = t1.item and rownum = 1) orgretl,
       t2.item_parent pitem
from smr_staging_e3_item_store t1, item_master t2
where t1.item = t2.item;
--------------------------------------------------------------------------------
--cursor casepack_update is
--select t1.rowid,
--       t2.supp_pack_size casepack
--from smr_staging_e3_item_store t1, item_supp_country t2
--where t1.item = t2.item
--  and t1.primary_supp = t2.supplier;
--------------------------------------------------------------------------------
cursor weight_update is
select t1.rowid,
       nvl(t2.net_weight,0) nwgt,
       nvl(t2.stat_cube,0) cubea
from smr_staging_e3_item_store t1, item_supp_country_dim t2
where t1.item = t2.item;
--------------------------------------------------------------------------------
cursor district_update is
select t1.rowid,
       nvl(t2.district,0) dstr
from smr_staging_e3_item_store t1, store t2
where t1.store = t2.store;
--------------------------------------------------------------------------------
cursor vpn_update is
select t1.rowid,
       SUBSTR(t2.vpn,1,18) vpna
from smr_staging_e3_item_store t1, item_supplier t2
where t1.primary_supp = to_char(t2.supplier)
   AND t1.item = t2.item;
--------------------------------------------------------------------------------
cursor group_update is
select t1.rowid,
       t2.dept dpt, t2.class cls, t2.subclass subc, t4.division dvn
from smr_staging_e3_item_store t1, item_master t2, deps t3, groups t4
where t1.item = t2.item
  and t2.dept = t3.dept
  and t3.group_no = t4.group_no;
--------------------------------------------------------------------------------
cursor uda_update is
select t1.rowid,
       t2.uda_id udaid, t2.uda_value udavalue
from smr_staging_e3_item_store t1, uda_item_lov t2
where t1.item = t2.item
  and t2.uda_id = 2
  and t2.uda_value =1;
--------------------------------------------------------------------------------
------------------------------------------------06/19/2012----------------------
----- back to the previous version -------------6/30/2012 --------------------
/*CURSOR UDA_UPDATE IS
SELECT T1.ROWID,
       T3.UDA_ID UDAID,
       T3.UDA_VALUE UDAVALUE
 FROM  SMR_STAGING_E3_ITEM_STORE T1,
       ITEM_MASTER T2,
       (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*       DISTINCT ITEM, UDA_ID, UDA_VALUE
           FROM UDA_ITEM_LOV
          WHERE UDA_ID= 2) T3
WHERE  T1.ITEM = T2.ITEM
   AND T2.ITEM = T3.ITEM
   AND ((T2.ITEM_LEVEL = 2 AND T3.UDA_VALUE = 1) OR (T2.ITEM_LEVEL = 1 AND T3.UDA_VALUE = 2))
   AND T2.SELLABLE_IND = 'Y';  */
--------------------------------------------------------------------------------
CURSOR ITEM_STORE_COUNT IS
SELECT COUNT(*)
FROM SMR_STAGING_E3_ITEM_STORE;
--------------------------------------------------------------------------------
CURSOR CHANGE_ITEM IS
SELECT  'E3T'||
         lpad((nvl(primary_supp,0)),8,'0')||
        'NONE '||
        'V'||
        '     '||
        rpad(lpad(to_char(item),11,'0'),18,' ')||
        to_char(lpad(store,5,0))||
        lpad((nvl(av_cost,0) * 10000),9,0)||
        lpad((nvl(selling_retail,0) * 10000),9,0)||
        lpad(nvl(package_size,1),7,0)||
 ---       lpad(1,7,0)||
 -- 8/1/11       '0000001'||
    lpad(nvl(package_size,1),7,0)||
 --
        lpad((nvl(net_weight,0) * 1000),7,0)||
 -- 8/1/11       lpad((0.010 * 1000),7,0)||
        lpad((nvl(selling_retail,0) * 1000),7,0)||
        rpad(nvl(item_desc, ' '),35,' ')||
 ---       nvl(standard_uom,'  ')||
        'EA'||    -- 8/1/11
        decode(status,NULL,' ','D')||
        '                  '||
        lpad(0,8,0)||
        lpad(0,8,0)||
        '  '||
        rpad(to_char(nvl(district,0)),5,' ')||
        rpad(nvl(vpn,' '),18,' ')||
        '          '||
        rpad(nvl(upc,' '),15,' ')||
        '          '||
        lpad(0,7,0)||
        0||
        lpad(0,7,0)||
        lpad(0,8,0)||
        0||
        lpad(0,7,0)||
        lpad(0,7,0)||
        lpad(0,3,0)||
        lpad(0,3,0)||
        lpad(1,5,0)||
        lpad(1,5,0)||
        lpad(0,5,0)||
        lpad(0,5,0)||
        lpad(0,5,0)||
        lpad(0,5,0)||
        lpad(0,5,0)||
        lpad(1,5,0)||
        lpad(0,3,0)||
        lpad(0,5,0)||
        lpad(0,3,0)||
        lpad(1,5,0)||
        lpad(0,2,0)||
        rpad(to_char(division),5,' ')||
        rpad(to_char(dept),5,' ')||
        rpad(to_char(classa),5,' ')||
        rpad(to_char(subclass),5,' ')||
        '     '||
        '     '||
        ' '||
        '     '||
        '        '||
        rpad(nvl(color,' '),12,' ')||
        rpad(nvl(sizea,' '),12,' ')||
        rpad(nvl(item_parent,' '),12,' ')||
        lpad(0,7,0)||
        lpad(0,7,0)||
        ' '||
        '          '||
        lpad(0,7,0)||
        lpad(0,7,0)||
        '          '||
        0||
        action_flag output_line
--        decode(action_flag,'D',action_flag,' ') output_line
  FROM SMR_STAGING_E3_ITEM_STORE
 ORDER BY ITEM, STORE;
---------------------------------------------------------------------------------
CURSOR UPDATE_CLOSED_STORE IS
SELECT STORE FROM STORE WHERE STORE < 900
AND STORE_CLOSE_DATE < GET_VDATE + 1
ORDER BY STORE;
--------------------------------------------------------------------------------
CURSOR UPDATE_ITEM_STORE IS
SELECT SUPPLIER, STORE
  FROM SMR_STAGING_E3_SUPP_STORE
 WHERE ACTION_FLAG = 'D';
--------------------------------------------------------------------------------
L_extract_file  UTL_FILE.FILE_TYPE;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
BEGIN
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE 'create table backup_smr_staging_e3_item as select * from smr_staging_e3_item';
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ITEM_TEMP';
commit;
--------------------------------------------------------------------------------
--- Do not process any 'D' item still in replenishment VER 1.21-----------------
--------------------------------------------------------------------------------
------------------------------------------------------06/19/2012----------------
DELETE FROM SMR_STAGING_E3_ITEM
WHERE ACTION_FLAG = 'D'
  AND ITEM IN (SELECT ITEM FROM UDA_ITEM_LOV WHERE UDA_ID = 2 AND UDA_VALUE = 1);
commit;
----- back to the previous version -------------6/30/2012 --------------------
/*delete FROM SMR_STAGING_E3_ITEM
WHERE ACTION_FLAG = 'D'
  AND ITEM IN (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*                      distinct T1.ITEM
                 FROM UDA_ITEM_LOV T1,
                      ITEM_MASTER T2
                  WHERE T1.ITEM = T2.ITEM
                    AND ((T2.ITEM_LEVEL = 2 AND T1.UDA_ID = 2 AND T1.UDA_VALUE = 1) OR (T2.ITEM_LEVEL = 1 AND T1.UDA_ID = 2 AND T1.UDA_VALUE = 2))
                    AND T2.SELLABLE_IND = 'Y'); */
/*commit; */
--------------------------------------------------------------------------------
open csr01;
loop
fetch csr01 into t_xitem, t_xflag, t_xdate;
exit when csr01%notfound;
insert into smr_staging_e3_item_temp
values (t_xitem, t_xflag, t_xdate);
end loop;
close csr01;
COMMIT;
--------------------------------------------------------------------------------
--------------------------------------------06/20/2012 Vonda requested----------
--------- Insert into on hand if the item is new -------------------------------
INSERT INTO SMR_STAGING_E3_ONHAND
SELECT DISTINCT T1.ITEM, T2.STORE, 'N', T1.UPDTME
FROM SMR_STAGING_E3_ITEM_TEMP T1,
     STORE T2
WHERE T1.ACTION_FLAG = 'N'
  AND T2.STORE < 800
  AND NVL(T2.STORE_CLOSE_DATE,GET_VDATE+1) > GET_VDATE;

COMMIT;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ITEM';
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ITEM_SELECTED';
commit;
--------------------------------------------------------------------------------
OPEN CSR02;
LOOP FETCH CSR02 BULK COLLECT INTO t_item, t_flag LIMIT L_MAX_FETCH;
EXIT WHEN t_item.count = 0;
FORALL I IN 1..T_ITEM.COUNT
INSERT INTO SMR_STAGING_E3_ITEM_SELECTED
VALUES(t_item (I), t_flag (I));
END LOOP;
CLOSE CSR02;
COMMIT;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ITEM_STORE';
commit;
--------------------------------------------------------------------------------
open item_store;
loop
fetch item_store into l_item, l_store, l_flag;
exit when item_store%notfound;
insert into smr_staging_e3_item_store
values
(
  l_item,
  l_store,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  l_flag);
end loop;
close item_store;
commit;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
for rec in upc_update loop
update smr_staging_e3_item_store set upc = rec.itemb
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
--8/1/11
--for rec in supplier_update loop
--update smr_staging_e3_item_store
--      set primary_supp = rec.psupp, av_cost = rec.avcost
--where rowid = chartorowid(rec.rowid);
--end loop;
for rec in supplier_update loop
update smr_staging_e3_item_store
      set primary_supp = rec.psupp,
          av_cost = rec.uncost,
          package_size = rec.spz
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
for rec in retail_update loop
update smr_staging_e3_item_store set selling_retail = rec.sur
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
for rec in master_update loop
update smr_staging_e3_item_store
---         set package_size = rec.pkgsz,
        Set item_desc = rec.itemdesc,
             standard_uom = rec.stuom,
             color = rec.clr,
             sizea = rec.sze,
             selling_retail = decode(selling_retail,NULL,rec.orgretl,selling_retail),
         item_parent = rec.pitem
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
--8/1/11
--For rec in casepack_update loop
--update smr_staging_e3_item_store
--         set package_size = rec.casepack
--where rowid = chartorowid(rec.rowid);
--end loop;
--commit;
--------------------------------------------------------------------------------
for rec in weight_update loop
update smr_staging_e3_item_store
        set net_weight = rec.nwgt,
            stat_cube = rec.cubea
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
for rec in district_update loop
update smr_staging_e3_item_store
        set district = rec.dstr
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
for rec in vpn_update loop
update smr_staging_e3_item_store
        set vpn = rec.vpna
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
for rec in group_update loop
update smr_staging_e3_item_store
        set division = rec.dvn, subclass = rec.subc, classa = rec.cls, dept = rec.dpt
where rowid = chartorowid(rec.rowid);
end loop;
commit;
--------------------------------------------------------------------------------
for rec in uda_update loop
update smr_staging_e3_item_store
        set status = ' '
where rowid = chartorowid(rec.rowid);
end loop;
COMMIT;
--------------------------------------------------------------------------------
FOR RECS IN update_closed_store
  LOOP
  UPDATE SMR_STAGING_E3_ITEM_STORE
     SET ACTION_FLAG = 'D'
   WHERE STORE = RECS.STORE;
  END LOOP;
COMMIT;
--------------------------------------------------------------------------------
FOR RECS IN update_item_store
  LOOP
  UPDATE SMR_STAGING_E3_ITEM_STORE
     SET ACTION_FLAG = 'D'
   WHERE PRIMARY_SUPP = RECS.SUPPLIER
     AND STORE = RECS.STORE
     AND ACTION_FLAG != 'D';
  END LOOP;
COMMIT;
--------------------------------------------------------------------------------
L_extract_filename := 'SMR_E3_ITEM'||'.'||l_timestamp||'.dat';
L_extract_file := UTL_FILE.FOPEN(l_path,
                                 L_extract_filename,
                                 'w',
                                 g_linesize);
OPEN  ITEM_STORE_COUNT;
FETCH ITEM_STORE_COUNT INTO L_ITEM_STORE_COUNT;
CLOSE ITEM_STORE_COUNT;
OPEN CHANGE_ITEM;
--------------------------------------------------------------------------------
FOR IKX IN 1..L_ITEM_STORE_COUNT LOOP
FETCH CHANGE_ITEM INTO OUTPUT_LINE;
L_line := output_line;
UTL_FILE.PUT_LINE(L_extract_file, L_line);
END LOOP;
commit;
--------------------------------------------------------------------------------
CLOSE CHANGE_ITEM;
UTL_FILE.FCLOSE(L_extract_file);
commit;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE 'drop table backup_smr_staging_e3_item';
--------------------------------------------------------------------------------
COMMIT;
--------------------------------------------------------------------------------
RETURN TRUE;
--------------------------------------------------------------------------------
EXCEPTION
    when UTL_FILE.INVALID_OPERATION then
       O_error_message := sql_lib.create_msg ('SMR_E3_OPERATION',
                                              L_extract_filename,
                                              L_operation);
       RETURN FALSE;
    when UTL_FILE.INVALID_PATH then
         O_error_message := sql_lib.create_msg ('SMR_E3_PATH',
                                              l_path,
                                              L_extract_filename);
        RETURN FALSE;
    when OTHERS then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR',
                                               SQLERRM,
                                              'SMR_E3_ITEM');
    RETURN FALSE;
END SMR_E3_ITEM_SQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION SMR_E3_ONHAND_SQL(O_error_message IN OUT VARCHAR2)
   RETURN BOOLEAN IS
--------------------------------------------------------------------------------
--Program Name : smr_E3_onhand_sql
--Description  : This script will populate SMR_E3 for ONHAND interface
--               from RMS to E3 on iSeries.
--------------------------------------------------------------------------------
    L_program             VARCHAR2(61)   := PACKAGE_NAME || '.SMR_E3_ONHAND_SQL';
    L_MAX_FETCH           NUMBER (10) := 100000;
    I                     NUMBER(10) := 0;
    L_timestamp           VARCHAR2(17) :=
                          to_char(systimestamp,'YYYYMMDDHH24MISS');
--
    L_extract_filename    VARCHAR2(4000);
    L_line                VARCHAR2(3000);
    g_linesize            NUMBER(4) := 3000;
    L_operation           VARCHAR2(2000) :=
                          'UTL_FILE.FOPEN with logical path '||'MMOUT';
    l_path                VARCHAR2(5) := 'MMOUT';
    output_line           VARCHAR2(3000);
    t_xitem               VARCHAR2(25);
    t_xlocation           NUMBER(10);
    T_XFLAG               VARCHAR2(1);
    T_XDATE               VARCHAR2(20);
    V_ITEM                VARCHAR2(11);
    V_LOC                 NUMBER;
    V_FLAG                VARCHAR2(1);
    V_ONORDER             number;
    LOOP_COUNT            NUMBER(5);
    O_QUANTITY            NUMBER;
    o_pack_quantity       number;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
CURSOR CSR01 IS
SELECT DISTINCT T1.ITEM, T1.LOCATION, T1.ACTION_FLAG
--, TO_CHAR(t1.UPDTME,'DD-MM-YYYY HH24:MM:SS')
FROM SMR_STAGING_E3_ONHAND T1,
     ITEM_MASTER T2
WHERE T1.ITEM = T2.ITEM
--  AND T2.ITEM_LEVEL = T2.TRAN_LEVEL
--  AND T2.ITEM_LEVEL = 2
  AND T2.ITEM_LEVEL in (1,2)  --- 07/09/2012
  AND T2.SELLABLE_IND = 'Y';

--------------------------------------------------------------------------------
------------------------------------------------------------06/19/2012----------
----------Made change 06/27/2012 to get unique item, location, action_flag -----
/*CURSOR CSR01 IS
SELECT DISTINCT t1.ITEM, t1.LOCATION, t1.ACTION_FLAG, TO_CHAR(t1.UPDTME,'DD-MM-YYYY HH24:MM:SS')
FROM SMR_STAGING_E3_ONHAND T1,
     ITEM_MASTER T2,
     (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*      DISTINCT ITEM, UDA_ID, UDA_VALUE
          FROM UDA_ITEM_LOV
         WHERE UDA_ID= 2) T3
WHERE T1.ITEM = T2.ITEM
  AND T2.ITEM = T3.ITEM
  AND ((T2.ITEM_LEVEL = 2 AND T3.UDA_VALUE = 1) OR (T2.ITEM_LEVEL = 1 AND T3.UDA_VALUE = 2))
   AND T2.SELLABLE_IND = 'Y'; */
----- back to the previous version -------------6/30/2012 --------------------
/*CURSOR CSR01 IS
SELECT DISTINCT T1.ITEM, T1.LOCATION, T1.ACTION_FLAG
FROM  (SELECT ITEM, LOCATION, ACTION_FLAG,
              ROW_NUMBER () OVER (PARTITION BY item, location ORDER BY item, LOCATION) NUM
        FROM SMR_STAGING_E3_ONHAND
        GROUP BY ITEM, LOCATION, action_flag) T1,
       ITEM_MASTER T2,
       (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*            DISTINCT ITEM, UDA_ID, UDA_VALUE
                FROM UDA_ITEM_LOV
                WHERE UDA_ID= 2) T3
WHERE T1.ITEM = T2.ITEM
  AND T1.NUM = 1
  AND ((T2.ITEM_LEVEL = 2 AND T3.UDA_VALUE = 1) OR (T2.ITEM_LEVEL = 1 AND T3.UDA_VALUE = 2))
  AND T2.SELLABLE_IND = 'Y'
  ORDER BY T1.ITEM, T1.LOCATION; */

--------------------------------------------------------------------------------
CURSOR  CSR02 IS
SELECT  distinct b.item, b.location, c.action_flag
  FROM (SELECT item, location, MAX(updtme) xtime
          FROM smr_staging_e3_onhand_temp
        GROUP BY item, location) b,
      SMR_STAGING_E3_ONHAND_TEMP C
 WHERE    b.item     = c.item
      AND B.LOCATION = C.LOCATION
      AND B.XTIME    = C.UPDTME;

------------------------------------------------------------06/19/2012----------
----------Made change 06/27/2012 to get unique item, location, action_flag -----
--------------------------------------------------------------------------------
----- back to the previous version -------------6/30/2012 --------------------
/*CURSOR CSR02 IS
SELECT DISTINCT T1.ITEM, T1.LOCATION, T1.ACTION_FLAG
FROM  (SELECT ITEM, LOCATION, ACTION_FLAG,
              ROW_NUMBER () OVER (PARTITION BY item, LOCATION ORDER BY item, LOCATION) NUM
        FROM SMR_STAGING_E3_ONHAND_TEMP
        GROUP BY ITEM, LOCATION, action_flag) T1,
       ITEM_MASTER T2,
       (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*            DISTINCT ITEM, UDA_ID, UDA_VALUE
                FROM UDA_ITEM_LOV
                WHERE UDA_ID= 2) T3
WHERE T1.ITEM = T2.ITEM
  AND T1.NUM = 1
  AND ((T2.ITEM_LEVEL = 2 AND T3.UDA_VALUE = 1) OR (T2.ITEM_LEVEL = 1 AND T3.UDA_VALUE = 2))
  AND T2.SELLABLE_IND = 'Y'
  ORDER BY T1.ITEM, T1.LOCATION; */
--------------------------------------------------------------------------------

TYPE TblWorkId IS TABLE OF VARCHAR2 (200);
t_item                      TblWorkId := TblWorkId ();
t_location                  TblWorkId := TblWorkId ();
t_action_flag               TblWorkId := TblWorkId ();
--------------------------------------------------------------------------------
/* CURSOR EXTRACT_CUR IS
SELECT  T1.ITEM,
        t2.dept dpt,
        T1.LOCATION,
--        nvl(t3.primary_supp,0) psupp,
        nvl(t4.supplier,0) psupp, -- 5/31/2012
        nvl(t3.stock_on_hand,0) onhand,
        nvl(t3.customer_backorder,0) backorder,
        nvl(t3.in_transit_qty,0) intransitqty,
        nvl(t3.tsf_reserved_qty,0) tsfreservedqty,
        nvl(t3.rtv_qty,0) rtvreservedqty,
        NVL(T3.TSF_RESERVED_QTY,0) RESERVEDQTY,
        nvl(t3.non_sellable_qty,0) nsreservedqty,
        NVL(T3.CUSTOMER_RESV,0) CUSRESERVEDQTY
  FROM SMR_STAGING_E3_ONHAND_SELECTED t1, item_master t2, item_loc_soh t3, item_supp_country t4
 WHERE t1.item = t2.item
   AND T2.ITEM = T3.ITEM
   AND T1.LOCATION = T3.LOC
   AND T1.ITEM = T4.ITEM
   AND T4.PRIMARY_SUPP_IND = 'Y'; */

CURSOR EXTRACT_CUR IS
SELECT /*+ t1 INDEX(SMR_STG_E3_ONHAND_SELECTED_I2) */
        T4.ITEM itm,
        T2.DEPT DPT,
        T4.LOC loc,
        nvl(t3.supplier,0) psupp,
        nvl(t4.stock_on_hand,0) onhand,
        nvl(t4.customer_backorder,0) backorder,
        nvl(t4.in_transit_qty,0) intransitqty,
        nvl(t4.tsf_reserved_qty,0) tsfreservedqty,
        nvl(t4.rtv_qty,0) rtvreservedqty,
        NVL(T4.TSF_RESERVED_QTY,0) RESERVEDQTY,
        nvl(t4.non_sellable_qty,0) nsreservedqty,
        NVL(T4.CUSTOMER_RESV,0) CUSRESERVEDQTY
  FROM SMR_STAGING_E3_ONHAND_SELECTED T1,
       ITEM_MASTER T2,
       ITEM_SUPP_COUNTRY T3,
       ITEM_LOC_SOH T4
 WHERE T1.ITEM = T4.ITEM
   AND T1.item = T2.item
   AND T2.ITEM = T3.ITEM
   AND T1.LOCATION = T4.LOC
   AND T3.PRIMARY_SUPP_IND = 'Y';
--------------------------------------------------------------------------------
CURSOR extract_salesunit IS
SELECT t2.item,
       t2.location,
       sum(t2.units) salesqty
  FROM SMR_STAGING_E3_ONHAND_SELECTED t1,
       smr_e3_tran_data t2
WHERE  t1.item = t2.item
   AND t1.location = t2.location
   AND T2.TRAN_CODE = 1
   AND T2.PROCESSED_FLAG = 'U'
--- made change for 1.22 6/04/2012
   AND T2.UNITS > 0
GROUP BY T2.ITEM,
         t2.location;
--------------------------------------------------------------------------------
CURSOR  EXTRACT_ALLOCQTY IS
SELECT  T1.ITEM idITEM,
        T1.LOCATION idLOC,
        SUM(NVL(T3.QTY_ALLOCATED,0)) IDALLOCQTY,
        SUM(NVL(T3.QTY_TRANSFERRED,0)) idTRANSQTY
  FROM  SMR_STAGING_E3_ONHAND_SELECTED t1,
        alloc_header t2,
        alloc_detail t3
 WHERE  t1.item = t2.item
   AND  t2.alloc_no = t3.alloc_no
   AND  T1.LOCATION = T3.TO_LOC
   AND  T2.ORDER_NO IS NOT NULL
   -- 15-Sep-15 Added
   AND EXISTS (SELECT 'X'
                 FROM ORDHEAD O
                WHERE O.ORDER_NO = T2.ORDER_NO
                  AND O.INCLUDE_ON_ORDER_IND = 'Y')   
   AND  T2.STATUS IN ('A', 'R')
   AND  NVL(T3.QTY_ALLOCATED,0) > NVL(T3.QTY_TRANSFERRED,0) -- 03-Apr-2013 Added
   GROUP BY T1.ITEM, T1.LOCATION;
--------------------------------------------------------------------------------
CURSOR  EXTRACT_ORDQTY IS
SELECT  T1.ITEM,
        T1.LOCATION,
        SUM(T2.QTY_ORDERED) QTYORD,
        SUM(NVL(T2.QTY_RECEIVED,0)) QTYRCV
  FROM  SMR_STAGING_E3_ONHAND_SELECTED T1,
        ORDLOC T2,
        ORDHEAD T3
WHERE   T1.ITEM = T2.ITEM
  AND   T1.LOCATION = T2.LOCATION
  AND   T2.LOC_TYPE = 'S'
  AND   T2.QTY_ORDERED > NVL(T2.QTY_RECEIVED,0)
  AND   T2.ORDER_NO = T3.ORDER_NO
  AND   T3.STATUS = 'A'
  -- 15-Sep-15 Added
  AND   T3.INCLUDE_ON_ORDER_IND = 'Y'
  GROUP BY T1.ITEM, T1.LOCATION;
  ------------------------------------------------------------------------------
CURSOR  EXTRACT_INDIV_PACK IS
SELECT  T1.ITEM IDPITEM,
        T1.LOCATION IDPLOC,
        SUM(NVL(T4.QTY_ALLOCATED,0) * T2.ITEM_QTY) IDPALLOCQTY,
        SUM(NVL(T4.QTY_TRANSFERRED,0) * t2.item_qty) idpTRANSQTY
  FROM  SMR_STAGING_E3_ONHAND_SELECTED T1,
        PACKITEM_BREAKOUT T2,
        ALLOC_HEADER T3,
        ALLOC_DETAIL T4
 WHERE  T1.ITEM = T2.ITEM
   AND  T2.PACK_NO = T3.ITEM
   AND  T3.STATUS IN ('A','R')
   AND  T3.ORDER_NO IS NOT NULL
   -- 15-Sep-15 Added
   AND EXISTS (SELECT 'X'
                 FROM ORDHEAD O
                WHERE O.ORDER_NO = T3.ORDER_NO
                  AND O.INCLUDE_ON_ORDER_IND = 'Y')     
   AND  T3.ALLOC_NO = T4.ALLOC_NO
   AND  T1.LOCATION = T4.TO_LOC
   AND  T1.ITEM NOT IN (SELECT SKU_ITEM FROM SMR_STAGING_E3_ALLOC_PACKITEM)
   AND  NVL(T4.QTY_ALLOCATED,0) > NVL(T4.QTY_TRANSFERRED,0) -- 03-Apr-2013 Added
   GROUP BY T1.ITEM, T1.LOCATION;
--------------------------------------------------------------------------------
----------------CURSOR FOR PACK ITEM--------------------------------------------
--------------------------------------------------------------------------------
CURSOR  EXTRACT_PACKHEAD_ALLOC_QTY IS
SELECT  T1.PACK_ITEM,
        SUM(NVL(T3.QTY_ALLOCATED,0)) PACKHEADALLOC,
        SUM(NVL(T3.QTY_TRANSFERRED,0)) PACKHEADTRANS
  FROM  SMR_STAGING_E3_ALLOC_PACKHEAD T1,
        ALLOC_HEADER T2,
        ALLOC_DETAIL T3
 WHERE  T1.PACK_ITEM = T2.ITEM
   AND  T1.ALLOC_NO  = T2.ALLOC_NO
   AND  T2.ALLOC_NO  = T3.ALLOC_NO
   AND  T2.ORDER_NO  IS NOT NULL
   -- 15-Sep-15 Added
   AND EXISTS (SELECT 'X'
                 FROM ORDHEAD O
                WHERE O.ORDER_NO = T2.ORDER_NO
                  AND O.INCLUDE_ON_ORDER_IND = 'Y')    
   AND  T2.STATUS IN ('A', 'R')
   AND  NVL(T3.QTY_ALLOCATED,0) > NVL(T3.QTY_TRANSFERRED,0) -- 03-Apr-2013 Added
   GROUP BY T1.PACK_ITEM;
--------------------------------------------------------------------------------
CURSOR  EXTRACT_PACKHEAD_ONORDER_QTY IS
SELECT  T1.PACK_ITEM,
        SUM(T2.QTY_ORDERED) PACKHEADORD,
        SUM(NVL(T2.QTY_RECEIVED,0)) PACKHEADRCV
  FROM  SMR_STAGING_E3_ALLOC_PACKHEAD T1,
        ORDLOC T2,
        ORDHEAD T3
WHERE   T1.PACK_ITEM = T2.ITEM
  AND   T1.ORDER_NO = T2.ORDER_NO
  AND   T2.LOC_TYPE = 'S'
  AND   T2.QTY_ORDERED > NVL(T2.QTY_RECEIVED,0)
  AND   T2.ORDER_NO = T3.ORDER_NO
  AND   T3.STATUS = 'A'
  -- 15-Sep-15 Added
  AND   T3.INCLUDE_ON_ORDER_IND = 'Y'  
  GROUP BY T1.PACK_ITEM;
--------------------------------------------------------------------------------
CURSOR  EXTRACT_PACKITEM_ONORDER_QTY IS
SELECT  T1.SKU_ITEM SKUITEM,
        T2.LOCATION TOLOC,
        T2.QTY_ORDERED * T1.ITEM_QTY PACKITEMORD,
        NVL(T2.QTY_RECEIVED,0) * T1.ITEM_QTY PACKITEMRCV
  FROM  SMR_STAGING_E3_ALLOC_PACKITEM T1,
        ORDLOC T2,
        ORDHEAD T3
WHERE   T1.ORDER_NO = T2.ORDER_NO
  AND   T1.TO_LOC = T2.LOCATION
  AND   T2.LOC_TYPE = 'S'
  AND   T2.QTY_ORDERED > NVL(T2.QTY_RECEIVED,0)
  AND   T2.ORDER_NO = T3.ORDER_NO
  -- 15-Sep-15 Added
  AND   T3.INCLUDE_ON_ORDER_IND = 'Y'  
  AND   T3.STATUS = 'A';
--------------------------------------------------------------------------------
/*CURSOR EXTRACT_PACKITEM_CUR IS
SELECT  T1.ALLOC_NO PIALLOC,
        T1.SKU_ITEM PIITEM,
        T2.DEPT PIDPT,
        T1.TO_LOC PILOC,
--        NVL(T3.PRIMARY_SUPP,0) PIPSUPP,
        NVL(T4.supplier,0) PIPSUPP, ----- new from 5/31/2012 Ver 1.19
        NVL(T3.STOCK_ON_HAND,0) PIONHAND,
        NVL(T3.CUSTOMER_BACKORDER,0) PIBACKORDER,
        NVL(T3.IN_TRANSIT_QTY,0) PIINTRANSITQTY,
        NVL(T3.TSF_RESERVED_QTY,0) PITSFRESERVEDQTY,
        NVL(T3.RTV_QTY,0) PIRTVRESERVEDQTY,
        NVL(T3.TSF_RESERVED_QTY,0) PIRESERVEDQTY,
        NVL(T3.NON_SELLABLE_QTY,0) PINSRESERVEDQTY,
        NVL(T3.CUSTOMER_RESV,0) PICUSRESERVEDQTY
  FROM  SMR_STAGING_E3_ALLOC_PACKITEM T1, ITEM_MASTER T2, ITEM_LOC_SOH T3, item_supp_country t4
 WHERE  T1.SKU_ITEM = T2.ITEM
    AND T2.ITEM_LEVEL = 2
    AND T2.SELLABLE_IND = 'Y'
    AND T2.ITEM = T3.ITEM
    AND T1.TO_LOC = T3.LOC
    AND T1.SKU_ITEM = T4.ITEM
    AND T4.PRIMARY_SUPP_IND = 'Y';  */
--------------------------------------------------------------------------------
---------------------------------------------------------------06/19/2012-------
CURSOR EXTRACT_PACKITEM_CUR IS
SELECT  T1.ALLOC_NO PIALLOC,
        T1.SKU_ITEM PIITEM,
        T2.DEPT PIDPT,
        T1.TO_LOC PILOC,
        NVL(T4.supplier,0) PIPSUPP, ----- new from 5/31/2012 Ver 1.19
        NVL(T3.STOCK_ON_HAND,0) PIONHAND,
        NVL(T3.CUSTOMER_BACKORDER,0) PIBACKORDER,
        NVL(T3.IN_TRANSIT_QTY,0) PIINTRANSITQTY,
        NVL(T3.TSF_RESERVED_QTY,0) PITSFRESERVEDQTY,
        NVL(T3.RTV_QTY,0) PIRTVRESERVEDQTY,
        NVL(T3.TSF_RESERVED_QTY,0) PIRESERVEDQTY,
        NVL(T3.NON_SELLABLE_QTY,0) PINSRESERVEDQTY,
        NVL(T3.CUSTOMER_RESV,0) PICUSRESERVEDQTY
  FROM  SMR_STAGING_E3_ALLOC_PACKITEM T1,
        ITEM_MASTER T2,
        ITEM_LOC_SOH T3,
        item_supp_country t4
 WHERE  T1.SKU_ITEM = T2.ITEM
    AND T2.ITEM_LEVEL in (1,2)  --- 07/09/2012
--    AND T2.ITEM_LEVEL = 2  -- back to previous version
    AND T2.SELLABLE_IND = 'Y'
    AND T2.ITEM = T3.ITEM
    AND T1.TO_LOC = T3.LOC
    AND T1.SKU_ITEM = T4.ITEM
    AND T4.PRIMARY_SUPP_IND = 'Y';

--------------------------------------------------------------------------------
CURSOR EXTRACT_PACKITEM_SALESUNIT IS
SELECT T2.ITEM PIITEM,
       T2.LOCATION PILOC,
       SUM(T2.UNITS) PISALESQTY
  FROM SMR_STAGING_E3_ALLOC_PACKITEM T1,
       SMR_E3_TRAN_DATA T2
 WHERE T1.SKU_ITEM = T2.ITEM
   AND T1.TO_LOC = T2.LOCATION
   AND T2.TRAN_CODE = 1
   AND T2.PROCESSED_FLAG = 'U'
--- made change for 1.22 6/04/2012
   AND T2.UNITS > 0
   GROUP BY T2.ITEM,
         T2.LOCATION;
--------------------------------------------------------------------------------
CURSOR EXTRACT_PACKITEM IS
SELECT DISTINCT
       SKU_ITEM,
       TO_LOC,
       ON_ORDER
  FROm SMR_STAGING_E3_ALLOC_PACKITEM;
--------------------------------------------------------------------------------
CURSOR EXTRACT_ONORDER_TOTAL IS
SELECT T1.SKU_ITEM OOITEM,
       T1.TO_LOC OOLOC,
       T1.alloc_no OOALLNO,
       SUM(T4.QTY_TRANSFERRED * T2.ITEM_QTY) OOTRANS,
       sum(t4.qty_allocated * t2.item_qty) OOALLOC
FROM SMR_STAGING_E3_ALLOC_PACKITEM T1,
     PACKITEM_breakout T2,
     ALLOC_HEADER T3,
     ALLOC_DETAIL T4
WHERE T1.SKU_ITEM = T2.ITEM
  AND T2.PACK_NO = T3.ITEM
  AND T3.ALLOC_NO = T4.ALLOC_NO
  AND T1.TO_LOC = T4.TO_LOC
  AND T3.STATUS IN ('A','R')
   -- 15-Sep-15 Added
   AND (EXISTS (SELECT 'X'
                 FROM ORDHEAD O
                WHERE O.ORDER_NO = T3.ORDER_NO
                  AND O.INCLUDE_ON_ORDER_IND = 'Y') 
        OR T3.ORDER_NO is null )             
  AND NVL(T4.QTY_ALLOCATED,0) > NVL(T4.QTY_TRANSFERRED,0) -- 03-Apr-2013 Added
  group by t1.sku_item, t1.to_loc, t1.alloc_no;

----------------------WRITE OUTPUT----------------------------------------------
--------------------------------------------------------------------------------
/* CURSOR CHANGE_ONHAND IS
select  'E3T'||
        lpad(primary_supp,8,0)||
        'NONE '||
        'V'||
        rpad(to_char(dept),5,' ')||
        rpad(lpad(item,11,'0'),18,' ')||
        to_char(lpad(location,5,0))||
        LPAD(ON_HAND,7,0)||
        lpad(on_order,7,0)||
        lpad(back_order,7,0)||
        lpad(sales_units,7,0)||
        lpad(0,7,0)||
        lpad(0,7,0)||
        lpad(0,7,0)||
       '               '||
        LPAD(0,7,0)||
--       lpad(in_transit_qty,7,0)||  -- Vonda requested put zero 5/21/2012
       LPAD(0,7,0)||
--       LPAD(TSF_RESERVED_QTY,7,0)|| -- Vonda requested put zero 5/25/2012
       1 OUTPUT_LINE
  FROM SMR_STAGING_E3_ONHAND_SELECTED; */
--------------------------------------------------------------------------------
/*CURSOR CHANGE_ONHAND IS
SELECT  'E3T'||
        lpad(t1.primary_supp,8,0)||
        'NONE '||
        'V'||
        RPAD(TO_CHAR(T1.DEPT),5,' ')||
        RPAD(LPAD(T1.ITEM,11,'0'),18,' ')||
        TO_CHAR(LPAD(T1.LOCATION,5,0))||
        LPAD(T1.ON_HAND,7,0)||
        LPAD(T1.ON_ORDER,7,0)||
        LPAD(T1.BACK_ORDER,7,0)||
        lpad(t1.sales_units,7,0)||
        lpad(0,7,0)||
        lpad(0,7,0)||
        lpad(0,7,0)||
       '               '||
        LPAD(0,7,0)||
--       lpad(in_transit_qty,7,0)||  -- Vonda requested put zero 5/21/2012
       LPAD(0,7,0)||
--       LPAD(TSF_RESERVED_QTY,7,0)|| -- Vonda requested put zero 5/25/2012
       1 OUTPUT_LINE
  FROM SMR_STAGING_E3_ONHAND_SELECTED T1,
       ITEM_MASTER T2        -- added 6/7/2012
 WHERE T1.ITEM = T2.ITEM
--   AND T2.ITEM_LEVEL = T2.TRAN_LEVEL -- added 6/8/2012
   AND T2.ITEM_LEVEL = 2
   AND T2.SELLABLE_IND = 'Y';  -- added 6/7/2012 */
--------------------------------------------------------------------------------
----------------------------------------------------------06/19/2012------------
CURSOR CHANGE_ONHAND IS
SELECT  'E3T'||
        lpad(t1.primary_supp,8,0)||
        'NONE '||
        'V'||
        RPAD(TO_CHAR(T1.DEPT),5,' ')||
        RPAD(LPAD(T1.ITEM,11,'0'),18,' ')||
        TO_CHAR(LPAD(T1.LOCATION,5,0))||
        LPAD(T1.ON_HAND,7,0)||
        LPAD(T1.ON_ORDER,7,0)||
        LPAD(T1.BACK_ORDER,7,0)||
        lpad(t1.sales_units,7,0)||
        lpad(0,7,0)||
        lpad(0,7,0)||
        lpad(0,7,0)||
       '               '||
        LPAD(0,7,0)||
        LPAD(0,7,0)||
        1 OUTPUT_LINE
  FROM SMR_STAGING_E3_ONHAND_SELECTED T1,
       ITEM_MASTER T2
 WHERE T1.ITEM = T2.ITEM
   AND T2.ITEM_LEVEL IN (1, 2) -- 07/09/2012
--   AND T2.ITEM_LEVEL = 2 -- back to previous version
   and t2.sellable_ind = 'Y';
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
L_extract_file  UTL_FILE.FILE_TYPE;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
BEGIN
--- EXECUTE IMMEDIATE  'create TABLE BACKUP_SMR_STAGING_E3_ONHAND as select * from SMR_STAGING_E3_ONHAND';
EXECUTE IMMEDIATE  'create TABLE BACKUP_SMR_STAGING_E3_ALLOC as select * from SMR_STAGING_E3_ALLOC';
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ONHAND_TEMP';
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ALLOC_TEMP';
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ALLOC_PACKHEAD';
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ALLOC_PACKITEM';
--------------------------------------------------------------------------------
--------------------------------07/02/12----------------------------------------
DELETE
  FROM SMR_E3_TRAN_DATA
 WHERE PROCESSED_FLAG = 'P'
   OR (UNITS < 0 AND PROCESSED_FLAG = 'U');
COMMIT;
--------------------------------------------------------------------------------
--------------------------------07/02/12---Vonda's Query------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ONHAND';
COMMIT;
--------------------------------------------------------------------------------
/*INSERT INTO SMR_STAGING_E3_ONHAND
(Select distinct  L.Item,L.Loc, 'C' , sysdate
From  Item_loc L,
      Item_Master I,
      Uda_Item_Lov U,
      item_supp_country s
  Where L.item = i.item
   AND I.Item = U.Item
   AND U.item = s.item
   And U.Uda_Id = 2
   And U.Uda_Value = 1
   AND I.ITEM_LEVEL = 2
   AND I.SELLABLE_IND = 'Y'); */

-------------------------------------------------07/09/12-----------------------
INSERT INTO SMR_STAGING_E3_ONHAND
Select distinct  L.Item,L.Loc, 'C' , sysdate
From  Item_loc L,
      Item_Master I,
      Uda_Item_Lov U
  Where L.item = i.item
   AND I.Item = U.Item
   AND I.SELLABLE_IND = 'Y'
   AND ((I.ITEM_LEVEL = 1 AND U.UDA_ID = 2 AND U.UDA_VALUE = 2)
        OR  (I.ITEM_LEVEL = 2 AND U.UDA_ID = 2 AND U.UDA_VALUE = 1));

COMMIT;
--------------------------------------------------------------------------------

INSERT INTO SMR_STAGING_E3_ONHAND
SELECT DISTINCT INSERT_ITEM, INSERT_LOC, 'C', INSERT_UPDTME
FROM
(SELECT A.ITEM BASE_ITEM,
        A.LOCATION BASE_LOCATION,
        B.ITEM INSERT_ITEM,
        B.LOCATION INSERT_LOC,
        B.TRAN_DATA_TIMESTAMP INSERT_UPDTME
   FROM SMR_STAGING_E3_ONHAND A,
        SMR_E3_TRAN_DATA B
  WHERE b.ITEM = a.ITEM (+)
    AND b.LOCATION = a.LOCATION  (+)
    AND A.LOCATION IS NULL
    AND B.TRAN_CODE = 1
    AND B.PROCESSED_FLAG = 'U'     -- added 6/11/2012
    ORDER BY B.ITEM, B.LOCATION);
    COMMIT;
--------------------------------------------------------------------------------
---------------------backup the staging to temp---------------------------------
INSERT INTO SMR_STAGING_E3_ALLOC_TEMP
SELECT *
FROM SMR_STAGING_E3_ALLOC;
COMMIT;
---------------------6/27/2012 made change to get only one record by item-------
---------------------Back to previous version 0630/2012-------------------------
/*INSERT INTO smr_staging_e3_alloc_temp
SELECT t.alloc_no, t.order_no, t.item, t.status, t.ALLOC_METHOD, t.RELEASE_DATE, t.ALLOC_PARENT, t.ACTION_FLAG, t.UPDTME
  FROM (SELECT DISTINCT ALLOC_NO, ORDER_NO, ITEM, STATUS, ALLOC_METHOD, RELEASE_DATE, ALLOC_PARENT, ACTION_FLAG, UPDTME,
               ROW_NUMBER () OVER (PARTITION BY ITEM ORDER BY ITEM DESC) rn
          FROM SMR_STAGING_E3_ALLOC
--         WHERE item = '3213055'
         ORDER BY RN) t
 WHERE RN = 1; */
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ALLOC';
commit;
--------------------------------------------------------------------------------
OPEN CSR01;
LOOP
FETCH CSR01 INTO T_XITEM, T_XLOCATION, T_XFLAG;
----, T_XDATE;
EXIT WHEN CSR01%NOTFOUND;
INSERT INTO SMR_STAGING_E3_ONHAND_TEMP
VALUES (T_XITEM, T_XLOCATION, T_XFLAG, TRUNC(SYSDATE));
COMMIT;
END LOOP;
CLOSE CSR01;
COMMIT;
--------------------------------------------------------------------------------
--------made change 06/27/2012 because CSR01 is changed-------------------------
--------------------------------------------------------------------------------
---------------------Back to previous version 0630/2012 -------------------
/*OPEN CSR01;
LOOP
FETCH CSR01 INTO T_XITEM, T_XLOCATION, T_XFLAG;
EXIT WHEN CSR01%NOTFOUND;
INSERT INTO SMR_STAGING_E3_ONHAND_TEMP
VALUES (T_XITEM, T_XLOCATION, T_XFLAG, TRUNC(SYSDATE));
COMMIT;
END LOOP;
CLOSE CSR01;
COMMIT; */
--------------------------------------------------------------------------------
--EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ONHAND';
--commit;
--------------------------------------------------------------------------------
---------------------PACKHEAD PROCESS-#1----------------------------------------
--------------------------------------------------------------------------------
INSERT INTO SMR_STAGING_E3_ALLOC_PACKHEAD
SELECT   T1.ALLOC_NO,
         T1.ORDER_NO,
         T1.ITEM,
         T1.STATUS,
         0,
         0,
         0,
         0,
         T1.ACTION_FLAG,
         T1.UPDTME
  FROM   SMR_STAGING_E3_ALLOC_TEMP T1,
         ITEM_MASTER T2
  WHERE  T1.ITEM = T2.ITEM
    AND  T2.PACK_IND = 'Y'
    AND  T1.STATUS in ('A','R');
COMMIT;
--------------------------------------------------------------------------------
---------------------PACKHEAD PROCESS-#2----------------------------------------
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_PACKHEAD_ALLOC_QTY LOOP
      UPDATE SMR_STAGING_E3_ALLOC_PACKHEAD
         SET QTY_TRANSFERRED = REC.PACKHEADTRANS,
             QTY_ALLOCATED = REC.PACKHEADALLOC
       WHERE PACK_ITEM = REC.PACK_ITEM;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
---------------------PACKHEAD PROCESS-#3----------------------------------------
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_PACKHEAD_ONORDER_QTY LOOP
      UPDATE SMR_STAGING_E3_ALLOC_PACKHEAD
         SET QTY_ORDERED = REC.PACKHEADORD,
             QTY_RECEIVED = REC.PACKHEADRCV
       WHERE PACK_ITEM = REC.PACK_ITEM;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
---------------------PACKITEM PROCESS-#1----------------------------------------
--------------------------------------------------------------------------------
---------------------Back to previous version 0630/2012 -------------------
INSERT INTO SMR_STAGING_E3_ALLOC_PACKITEM
SELECT   T1.ALLOC_NO,
         T1.ORDER_NO,
         T1.PACK_ITEM,
         T2.ITEM,
         T2.ITEM_QTY,
         T4.TO_LOC,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
--         T4.QTY_TRANSFERRED * T2.ITEM_QTY QTYTRANS,
--         T4.QTY_ALLOCATED * T2.ITEM_QTY QTYALLOC,
         0,
         0,
         T1.ACTION_FLAG,
         T1.UPDTME
  FROM   SMR_STAGING_E3_ALLOC_PACKHEAD T1,
         PACKITEM_BREAKOUT T2,
         ALLOC_HEADER T3,
         ALLOC_DETAIL T4,
         UDA_ITEM_LOV T5
  WHERE  T1.PACK_ITEM = T2.PACK_NO
    AND  T1.ALLOC_NO  = T3.ALLOC_NO
    AND  T3.ALLOC_NO  = T4.ALLOC_NO
------------------------------------    AND  T3.STATUS IN ('A','R')
    AND  T2.ITEM = T5.ITEM
    AND  ((T5.UDA_ID = 2 and T5.UDA_VALUE = 2) or (T5.UDA_ID = 2 and T5.UDA_VALUE = 1));
--    AND  T5.UDA_ID = 2
--    AND  T5.UDA_VALUE = 1;
COMMIT;
--------------------------------------------------------------------------------
-----------------------------------------------06/19/2012-----------------------
/*INSERT INTO SMR_STAGING_E3_ALLOC_PACKITEM
SELECT   T1.ALLOC_NO,
         T1.ORDER_NO,
         T1.PACK_ITEM,
         T2.ITEM,
         T2.ITEM_QTY,
         T4.TO_LOC,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         0,
         T1.ACTION_FLAG,
         T1.UPDTME
  FROM   SMR_STAGING_E3_ALLOC_PACKHEAD T1,
         PACKITEM_BREAKOUT T2,
         ALLOC_HEADER T3,
         ALLOC_DETAIL T4,
         ITEM_MASTER T5,
         (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*            DISTINCT ITEM, UDA_ID, UDA_VALUE
                FROM UDA_ITEM_LOV
               WHERE UDA_ID= 2) T6
  WHERE  T1.PACK_ITEM = T2.PACK_NO
    AND  T1.ALLOC_NO  = T3.ALLOC_NO
    AND  T3.ALLOC_NO  = T4.ALLOC_NO
    AND  T2.ITEM = T5.ITEM
    AND  T5.ITEM = T6.ITEM
    AND ((T5.ITEM_LEVEL = 2 AND T6.UDA_VALUE = 1) OR (T5.ITEM_LEVEL = 1 AND T6.UDA_VALUE = 2))
    AND T5.SELLABLE_IND = 'Y';

COMMIT; */

--------------------------------------------------------------------------------
---------------------PACKITEM PROCESS-#2----------------------------------------
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_PACKITEM_ONORDER_QTY LOOP
      UPDATE SMR_STAGING_E3_ALLOC_PACKITEM
         SET QTY_ORDERED = REC.PACKITEMORD,
             QTY_RECEIVED = REC.PACKITEMRCV
       WHERE SKU_ITEM = REC.SKUITEM
         AND TO_LOC = REC.TOLOC;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_ONORDER_TOTAL LOOP
UPDATE SMR_STAGING_E3_ALLOC_PACKITEM
   SET QTY_TRANSFERRED = REC.OOTRANS,
       QTY_ALLOCATED   = REC.OOALLOC
WHERE  SKU_ITEM = REC.OOITEM
  AND  TO_LOC  = REC.OOLOC;
---------------------------------------------  AND  ALLOC_NO = REC.OOALLNO;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
---------------------PACKITEM PROCESS-#3----------------------------------------
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_PACKITEM_CUR LOOP
    UPDATE SMR_STAGING_E3_ALLOC_PACKITEM
       SET
       DEPT = REC.PIDPT           ,
       PRIMARY_SUPP = REC.PIPSUPP   ,
       ON_HAND = REC.PIONHAND       ,
       BACK_ORDER = REC.PIBACKORDER ,
       IN_TRANSIT_QTY = REC.PIINTRANSITQTY,
       ON_ORDER = (QTY_ORDERED - QTY_RECEIVED) + (QTY_ALLOCATED - QTY_TRANSFERRED),
       TSF_RESERVED_QTY = REC.PITSFRESERVEDQTY + REC.PIRTVRESERVEDQTY + GREATEST(REC.PINSRESERVEDQTY,0) + REC.PICUSRESERVEDQTY + REC.PIBACKORDER
 WHERE ALLOC_NO = REC.PIALLOC
   AND SKU_ITEM = REC.PIITEM
   AND TO_LOC = REC.PILOC;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
---------------------PACKITEM PROCESS-#4----------------------------------------
--------------------------------------------------------------------------------
 FOR REC IN EXTRACT_PACKITEM_SALESUNIT LOOP
    UPDATE SMR_STAGING_E3_ALLOC_PACKITEM
       SET SALES_UNITS = REC.PISALESQTY
     WHERE SKU_ITEM = REC.PIITEM
       AND TO_LOC = REC.PILOC;

COMMIT;

    LOOP_COUNT := LOOP_COUNT + 1;

   UPDATE SMR_E3_TRAN_DATA
      SET PROCESSED_FLAG = 'P'
    WHERE ITEM = REC.PIITEM
      AND LOCATION = REC.PILOC
      AND PROCESSED_FLAG = 'U'
      AND TRAN_CODE = 1;

COMMIT;

    IF   LOOP_COUNT = 1000 THEN
      COMMIT;
      LOOP_COUNT := 0;
    END IF;

COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
---------------------ALLOC-ONHAND Regular PROCESS-#1----------------------------
---insert into smr_staging_e3_onhand from - ALLOC regular item------------------
--------------------------------------------------------------------------------
INSERT INTO SMR_STAGING_E3_ONHAND_TEMP
SELECT   DISTINCT
         T1.ITEM,
         T3.TO_LOC,
         T1.ACTION_FLAG,
         trunc(T1.UPDTME)
  FROM   SMR_STAGING_E3_ALLOC_TEMP T1,
         ALLOC_HEADER T2,
         ALLOC_DETAIL T3,
         ITEM_MASTER T4,
         UDA_ITEM_LOV T5
 WHERE  T1.ITEM = T2.ITEM
   AND  T2.ALLOC_NO = T1.ALLOC_NO
   AND  T2.ORDER_NO IS NOT NULL
--   AND  T2.STATUS IN ('A', 'R')
   AND  T2.ALLOC_NO = T3.alloc_no
   AND  T1.ITEM = T4.Item
   AND  T4.PACK_IND != 'Y'
   AND  T4.ITEM = T5.ITEM
   AND  T4.SELLABLE_IND = 'Y'
   AND ((T4.ITEM_LEVEL = 1 AND T5.UDA_ID = 2 AND T5.UDA_VALUE = 2)
        OR  (T4.ITEM_LEVEL = 2 AND T5.UDA_ID = 2 AND T5.UDA_VALUE = 1));
COMMIT;
--   AND  T4.ITEM_LEVEL = T4.TRAN_LEVEL
--   AND  T4.ITEM_LEVEL = 2
--   AND  T5.UDA_ID = 2
--   AND  T5.UDA_VALUE = 1;

--------------------------------------------------------------------------------
------------------------------------------------06/19/2012----------------------
---------------------Back to previous version 0630/2012 -------------------
/*INSERT INTO SMR_STAGING_E3_ONHAND_TEMP
SELECT   DISTINCT
         T1.ITEM,
         T3.TO_LOC,
         T1.ACTION_FLAG,
         trunc(T1.UPDTME)
  FROM   SMR_STAGING_E3_ALLOC_TEMP T1,
         ALLOC_HEADER T2,
         ALLOC_DETAIL T3,
         ITEM_MASTER T4,
         (SELECT /*+ index(U UDA_ITEM_LOV_I1) */
/*            DISTINCT ITEM, UDA_ID, UDA_VALUE
                FROM UDA_ITEM_LOV
               WHERE UDA_ID= 2) T5
 WHERE  T1.ITEM = T2.ITEM
   AND  T2.ALLOC_NO = T1.ALLOC_NO
   AND  T2.ORDER_NO IS NOT NULL
   AND  T2.ALLOC_NO = T3.ALLOC_NO
--   AND  T2.STATUS IN ('A','R')
   AND  T1.ITEM = T4.Item
   AND  T4.PACK_IND != 'Y'
   AND  T4.ITEM = T5.ITEM
   AND ((T4.ITEM_LEVEL = 2 AND T5.UDA_VALUE = 1) OR (T4.ITEM_LEVEL = 1 AND T5.UDA_VALUE = 2))
   AND T4.SELLABLE_IND = 'Y';
COMMIT; */
--------------------------------------------------------------------------------
INSERT INTO SMR_STAGING_E3_ONHAND_TEMP
 SELECT DISTINCT
        T1.SKU_ITEM,
        T3.TO_LOC,
        T1.ACTION_FLAG,
        trunc(T1.UPDTME)
  FROM SMR_STAGING_E3_ALLOC_PACKITEM T1,
       ALLOC_HEADER T2,
       ALLOC_DETAIL T3
  WHERE T1.SKU_ITEM = T2.ITEM
--    AND T2.STATUS IN ('A','R')
    AND T2.ORDER_NO IS NOT NULL
    AND T2.ALLOC_NO = T3.ALLOC_NO
    AND T1.TO_LOC = T3.TO_LOC;

COMMIT;
--------------------------------------------------------------------------------
EXECUTE IMMEDIATE  'TRUNCATE TABLE SMR_STAGING_E3_ONHAND_SELECTED';
--------------------------------------------------------------------------------
---------------------ALLOC PROCESS-#4-------------------------------------------
---insert into smr_staging_e3_onhand_selected from - ALLOC regular item---------
--------------------------------------------------------------------------------
OPEN CSR02;
LOOP
FETCH CSR02 BULK COLLECT INTO T_ITEM, T_LOCATION, T_ACTION_FLAG LIMIT L_MAX_FETCH;
EXIT WHEN T_ITEM.COUNT = 0;
FORALL I IN 1..T_ITEM.COUNT
INSERT INTO SMR_STAGING_E3_ONHAND_SELECTED
VALUES
(
        t_item (I),
        0,
        t_location(I),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        t_action_flag (I)
        );
COMMIT;
END LOOP;
COMMIT;
CLOSE CSR02;
COMMIT;
--------------------------------------------------------------------------------
---------------------ALLOC PROCESS-#5-------------------------------------------
---Update smr_staging_e3_onhand_selected from - regular item--------------------
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_CUR LOOP
    UPDATE SMR_STAGING_E3_ONHAND_SELECTED
    SET
       DEPT = REC.DPT             ,
       PRIMARY_SUPP = REC.PSUPP   ,
       ON_HAND = REC.ONHAND       ,
       BACK_ORDER = REC.BACKORDER ,
       IN_TRANSIT_QTY = REC.INTRANSITQTY,
       ON_ORDER = REC.INTRANSITQTY,
       TSF_RESERVED_QTY = REC.TSFRESERVEDQTY + REC.RTVRESERVEDQTY + GREATEST(REC.NSRESERVEDQTY,0) + REC.CUSRESERVEDQTY + REC.BACKORDER
 WHERE ITEM = REC.ITM
   AND LOCATION = REC.LOC;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
---------------------ALLOC PROCESS-#6-------------------------------------------
---Update SALES to smr_staging_e3_onhand_selected from - regular item-----------
--------------------------------------------------------------------------------
 FOR REC IN EXTRACT_SALESUNIT LOOP
    UPDATE SMR_STAGING_E3_ONHAND_SELECTED
       SET SALES_UNITS = REC.SALESQTY
     WHERE ITEM = REC.ITEM
       AND LOCATION = REC.LOCATION;

COMMIT;

    LOOP_COUNT := LOOP_COUNT + 1;

   UPDATE SMR_E3_TRAN_DATA
      SET PROCESSED_FLAG = 'P'
    WHERE ITEM = REC.ITEM
      AND LOCATION = REC.LOCATION
      AND PROCESSED_FLAG = 'U'
      AND TRAN_CODE = 1;
COMMIT;

    IF   LOOP_COUNT = 1000 THEN
      COMMIT;
      LOOP_COUNT := 0;
    END IF;
COMMIT;

END LOOP;
COMMIT;
---------------------ALLOC PROCESS-#7-------------------------------------------
---Update ON ORDER from allocated to smr_staging_e3_onhand_selected from--------
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_ALLOCQTY LOOP
      UPDATE SMR_STAGING_E3_ONHAND_SELECTED
         SET ON_ORDER = ON_ORDER + (REC.IDALLOCQTY - REC.IDTRANSQTY)
       WHERE ITEM = REC.IDITEM
         AND LOCATION = REC.idLOC;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_INDIV_PACK LOOP
      UPDATE SMR_STAGING_E3_ONHAND_SELECTED
         SET ON_ORDER = ON_ORDER + (REC.IDPALLOCQTY - REC.IDPTRANSQTY)
       WHERE ITEM = REC.IDPITEM
         AND LOCATION = REC.IDPLOC;
COMMIT;
END LOOP;
COMMIT;
---------------------ALLOC PROCESS-#8-------------------------------------------
---Update ON ORDER from ORDLOC to smr_staging_e3_onhand_selected from-----------
--------------------------------------------------------------------------------
FOR REC IN EXTRACT_ORDQTY LOOP
      UPDATE SMR_STAGING_E3_ONHAND_SELECTED
         SET ON_ORDER = ON_ORDER + (REC.QTYORD - REC.QTYRCV)
       WHERE ITEM = REC.ITEM
         AND LOCATION = REC.LOCATION;
COMMIT;
END LOOP;
COMMIT;
--------------------------------------------------------------------------------
------INSERT INTO SMR_STAGING_E3_ONHAND_SELECTED FROM PACKITEM -----------------
--------------------------------------------------------------------------------
OPEN EXTRACT_PACKITEM;
LOOP
FETCH EXTRACT_PACKITEM INTO V_ITEM, V_LOC, V_ONORDER;

EXIT WHEN EXTRACT_PACKITEM%NOTFOUND;

 SELECT 'Y' INTO V_FLAG
    FROM  SMR_STAGING_E3_ONHAND_SELECTED
   WHERE  ITEM = V_ITEM
     AND  LOCation = V_LOC
     union (select 'N'
              from dual
             where not exists (select 'x'
                                 FROM SMR_STAGING_E3_ONHAND_SELECTED
                                WHERE ITEM = V_ITEM
                                  and location = V_LOC));

IF V_FLAG = 'Y' THEN    --- when the item and location is in both side

   UPDATE SMR_STAGING_E3_ONHAND_SELECTED
      SET ON_ORDER = ON_ORDER + V_ONORDER
    WHERE ITEM = V_ITEM
      AND LOCATION = V_LOC;
COMMIT;

   ELSE  --- when the item and location is in packitem only

   INSERT INTO SMR_STAGING_E3_ONHAND_SELECTED
       SELECT  distinct
               SKU_ITEM,
               DEPT,
               TO_LOC,
               PRIMARY_SUPP,
               ON_HAND,
               ON_ORDER,
               BACK_ORDER,
               IN_TRANSIT_QTY,
               TSF_RESERVED_QTY,
               SALES_UNITS,
               ACTION_FLAG
         FROM  SMR_STAGING_E3_ALLOC_PACKITEM
        WHERE  SKU_ITEM = V_ITEM
          AND  TO_LOC = V_LOC;
COMMIT;
END IF;
COMMIT;

V_FLAG    := NULL;
V_ITEM    := NULL;
V_LOC     := 0;
V_ONORDER := 0;

END LOOP;
CLOSE EXTRACT_PACKITEM;
COMMIT;
--------------------------------------------------------------------------------
------UPDATE ZERO TO SMR_STAGING_E3_ONHAND_SELECTED when less than zero---------
--------------------------------------------------------------------------------
UPDATE SMR_STAGING_E3_ONHAND_SELECTED
SET ON_HAND = 0
WHERE ON_HAND < 0;
COMMIT;

UPDATE SMR_STAGING_E3_ONHAND_SELECTED
SET ON_ORDER = 0
WHERE ON_ORDER < 0;
COMMIT;

UPDATE SMR_STAGING_E3_ONHAND_SELECTED
SET BACK_ORDER = 0
WHERE BACK_ORDER < 0;
COMMIT;

UPDATE SMR_STAGING_E3_ONHAND_SELECTED
SET IN_TRANSIT_QTY = 0
WHERE IN_TRANSIT_QTY < 0;
COMMIT;

UPDATE SMR_STAGING_E3_ONHAND_SELECTED
SET TSF_RESERVED_QTY = 0
WHERE TSF_RESERVED_QTY < 0;
COMMIT;

UPDATE SMR_STAGING_E3_ONHAND_SELECTED
SET SALES_UNITS = 0
WHERE SALES_UNITS < 0;
COMMIT;

UPDATE SMR_STAGING_E3_ONHAND_SELECTED
SET ON_HAND = ON_HAND - TSF_RESERVED_QTY
WHERE ON_HAND > TSF_RESERVED_QTY
  AND TSF_RESERVED_QTY != 0;
COMMIT;

------------------------------------added 08/09/12 to remove duplicated records
DELETE FROM smr_staging_e3_onhand_selected t1
WHERE ROWID > (
      SELECT MIN(ROWID) FROM SMR_STAGING_E3_ONHAND_SELECTED t2
      WHERE t1.ITEM = t2.ITEM
        AND T1.LOCATION = T2.LOCATION);
COMMIT;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
L_extract_filename := 'SMR_E3_STOCK'||'.'||l_timestamp||'.dat';
L_extract_file := UTL_FILE.FOPEN(l_path,
                                 L_extract_filename,
                                 'w',
                                 g_linesize);
FOR EXT_OUT IN CHANGE_ONHAND LOOP
       L_LINE := EXT_OUT.OUTPUT_LINE;
       UTL_FILE.PUT_LINE(L_extract_file,
                         L_line);
END LOOP;
--------------------------------------------------------------------------------
UTL_FILE.FCLOSE(L_extract_file);
--------------------------------------------------------------------------------
--EXECUTE IMMEDIATE  'drop TABLE BACKUP_SMR_STAGING_E3_ONHAND';
EXECUTE IMMEDIATE  'drop TABLE BACKUP_SMR_STAGING_E3_ALLOC';
COMMIT;
--------------------------------------------------------------------------------
RETURN TRUE;

EXCEPTION
    when UTL_FILE.INVALID_OPERATION then
       O_error_message := sql_lib.create_msg ('SMR_E3_OPERATION',
                                              L_extract_filename,
                                              L_operation);
       RETURN FALSE;
    when UTL_FILE.INVALID_PATH then
         O_error_message := sql_lib.create_msg ('SMR_E3_PATH',
                                              l_path,
                                              L_extract_filename);
        RETURN FALSE;
    when OTHERS then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR',
                                               SQLERRM,
                                              'SMR_E3_ONHAND');
    RETURN FALSE;
END SMR_E3_ONHAND_SQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION SMR_E3_STORE_GROUP_SQL(O_error_message IN OUT VARCHAR2)
   RETURN BOOLEAN IS
--------------------------------------------------------------------------------
--Program Name : smr_E3_store_group_sql
--Description  : This script will populate SMR_E3 for STORE GROUP interface
--               from RMS to E3 for iSeries.
--------------------------------------------------------------------------------
    L_program             VARCHAR2(61)   := PACKAGE_NAME || '.SMR_E3_STORE_GROUP_SQL';
    L_MAX_FETCH           NUMBER (10) := 100000;
    I                     NUMBER(10) := 0;
    L_timestamp           VARCHAR2(17) :=
                          to_char(systimestamp,'YYYYMMDDHH24MISS');
    L_extract_filename    VARCHAR2(4000);
    L_line                VARCHAR2(3000);
    g_linesize            NUMBER(4) := 3000;
    L_operation           VARCHAR2(2000) :=
                          'UTL_FILE.FOPEN with logical path '||'MMOUT';
    l_path                VARCHAR2(5) := 'MMOUT';
    t_xloc                NUMBER(10);
    t_xflag               VARCHAR2(1);
    t_xdate               VARCHAR2(20);
    V_Count               NUMBER;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
/* CURSOR STORE_GROUP_CURSOR IS
SELECT    'E3T'
       || LPAD (d.Loc_list, 5, 0)
       || LPAD (d.Loc_list, 5, 0)
       || TO_CHAR (RPAD (h.Loc_list_Desc, 20))
       || TO_CHAR (RPAD (h.Loc_list_Desc, 20))
       || TO_CHAR (LPAD (d.Location, 5, 0))
       || '0'
          output_line
  FROM LOC_LIST_HEAD H, LOC_LIST_DETAIL D
 WHERE H.LOC_LIST = D.LOC_LIST;  */

--------------------------------------------------------------------------------
-- requested by Vonda 6/19/2012 to modify following in location_list.
--------------------------------------------------------------------------------
CURSOR STORE_GROUP_CURSOR IS
SELECT    'E3T'
       || LPAD (D.LOC_LIST, 10, 0)
       || LPAD (d.Loc_list, 10, 0)
       || TO_CHAR (RPAD (h.Loc_list_Desc, 20))
       || TO_CHAR (RPAD (h.Loc_list_Desc, 20))
       || TO_CHAR (LPAD (d.Location, 5, 0))
       || '0'
       output_line
  FROM LOC_LIST_HEAD H, LOC_LIST_DETAIL D
 WHERE h.Loc_List = d.Loc_List;
--------------------------------------------------------------------------------
L_extract_file  UTL_FILE.FILE_TYPE;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
BEGIN
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

Select count(*)
  into v_count
  From Loc_List_Head h,
       Loc_List_Detail d
 Where h.Loc_List = d.Loc_List;

L_extract_filename := 'SMR_E3_GROUP'||'.'||l_timestamp||'.dat';
L_extract_file := UTL_FILE.FOPEN(l_path,
                                 L_extract_filename,
                                 'w',
                                 g_linesize);
FOR ext_out in store_group_cursor loop
       L_line := ext_out.output_line;
       UTL_FILE.PUT_LINE(L_extract_file,
                         L_line);
END LOOP;

IF v_count > 0
  THEN
  RETURN TRUE;
ELSE
  RETURN FALSE;
END IF;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
   UTL_FILE.FCLOSE(L_extract_file);
--------------------------------------------------------------------------------
--COMMIT;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
EXCEPTION
    when UTL_FILE.INVALID_OPERATION then
         O_error_message := sql_lib.create_msg ('SMR_E3_OPERATION',
                                              L_extract_filename,
                                              L_operation);
       RETURN FALSE;
    when UTL_FILE.INVALID_PATH then
         O_error_message := sql_lib.create_msg ('SMR_E3_PATH',
                                              l_path,
                                              L_extract_filename);
       RETURN FALSE;
    when OTHERS then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR',
                                               SQLERRM,
                                              'SMR_E3_STORE_GROUP');
        RETURN FALSE;
END SMR_E3_STORE_GROUP_SQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION SMR_E3_LED_TIME_SQL(O_error_message IN OUT VARCHAR2)
   RETURN BOOLEAN IS
--------------------------------------------------------------------------------
--Program Name : smr_E3_Led_Time_sql
--Description  : This script will populate SMR_E3 for Leding Time interface
--               from RMS to E3 for iSeries.
--------------------------------------------------------------------------------
    L_program             VARCHAR2(61)   := PACKAGE_NAME || '.SMR_E3_LED_TIME_SQL';
    L_MAX_FETCH           NUMBER (20) := 100000;
    I                     NUMBER(20) := 0;
    L_timestamp           VARCHAR2(30) :=
                          to_char(systimestamp,'YYYYMMDDHH24MISS');
    L_extract_filename    VARCHAR2(4000);
    L_LINE                VARCHAR2(4000);
    g_linesize            NUMBER := 4000;
    L_operation           VARCHAR2(2000) :=
                          'UTL_FILE.FOPEN with logical path '||'MMOUT';
    l_path                VARCHAR2(10) := 'MMOUT';
    t_xloc                NUMBER(20);
    T_XFLAG               VARCHAR2(5);
    t_xdate               VARCHAR2(30);
    V_Count               NUMBER;
    v_Start_date          DATE;
    v_End_date            DATE;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
CURSOR LED_TIME_CURSOR IS
SELECT Distinct
          'E3T'
       || 'NONE'
       || LPAD (OH.supplier, 8, 0)
       || RPAD (lpad(to_char(T.Item),11,'0'),18,' ')
       || LPAD (T.Store, 5, 0)
       || LPAD (T.Quantity_Received, 7, 0)
       || T.Receive_Date
       || TO_CHAR (OH.Orig_Approval_Date, 'YYYYMMDD') output_line
  FROM alloc_header     ah,
       alloc_detail     ad,
       shipsku          sk,
       shipment         sh,
     (SELECT s.ref_no_1 order_no, s.item Item, s.location Store, SUM (s.units) Quantity_Received,
             TO_CHAR (s.tran_date, 'YYYYMMDD') Receive_Date
        FROM SMR_E3_TRAN_DATA S
       WHERE tran_code = 20
         AND PROCESSED_FLAG = 'U'
    GROUP BY s.item,
             s.location,
             s.tran_date,
             s.ref_no_1) T,
     (Select distinct O.Loc_type, O.Location, O.Pre_Mark_Ind, O.Supplier, O.order_no, O.vendor_order_no,
             O.Orig_Approval_Date
        From ORDHEAD O
       Where O.Loc_type = 'W'
         and O.Location Not in (9402, 9011)
         and O.vendor_order_no is not null
         and O.Status = 'A')  oh
 WHERE T.order_no   = oh.order_no
   and ah.order_no  = oh.order_no
   and ah.alloc_no  = ad.alloc_no
   and ah.alloc_no  = sk.distro_no
   and ad.to_loc    = sh.to_loc
   and sh.shipment  = sk.shipment
   and sk.distro_type = 'A'
   and sh.status_code = 'R';

--------------------------------------------------------------------------------
L_extract_file  UTL_FILE.FILE_TYPE;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
BEGIN
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

SELECT count(*)
  INTO v_count
  FROM SMR_E3_TRAN_DATA
 WHERE tran_code = 20
   AND PROCESSED_FLAG = 'U';

-- Following are the both option vdate and system date.
-- I will confirme from Vonda which date I should be using ?

SELECT TRUNC(VDATE)      START_DATE,
       (TRUNC(VDATE)-14) END_DATE
  INTO V_START_DATE, V_END_DATE
  FROM PERIOD;


L_extract_filename := 'SMR_E3_LEADT'||'.'||l_timestamp||'.dat';
L_extract_file := UTL_FILE.FOPEN(l_path,
                                 L_extract_filename,
                                 'w',
                                 g_linesize);


   IF v_count > 0

      THEN

        FOR ext_out in LED_TIME_CURSOR loop

             IF v_count > 0 then
               L_line := ext_out.output_line;
               UTL_FILE.PUT_LINE(L_extract_file,
                                 L_line);

               UPDATE SMR_E3_TRAN_DATA
                  SET PROCESSED_FLAG = 'P'
                WHERE TRAN_CODE = 20
                  AND PROCESSED_FLAG = 'U';

               COMMIT;

             END IF;

        END LOOP;

               DELETE
                 FROM SMR_E3_TRAN_DATA
                WHERE (TRUNC(TRAN_DATE) > V_START_DATE
                   OR TRUNC(TRAN_DATE)  < V_END_DATE)
                  AND PROCESSED_FLAG = 'P'
                  AND TRAN_CODE = 20;

      RETURN TRUE;

    ELSE

      O_error_message := sql_lib.create_msg ('There is no data to process for LEADTIME');

      RETURN FALSE;

    END IF;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
   UTL_FILE.FCLOSE(L_extract_file);
--------------------------------------------------------------------------------
--COMMIT;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
EXCEPTION

    when NO_DATA_FOUND then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR NO_DATA_FOUND',
                                              'SMR_E3_LED_TIME');

    when UTL_FILE.INVALID_OPERATION then
         O_error_message := sql_lib.create_msg ('SMR_E3_OPERATION',
                                              L_extract_filename,
                                              L_operation);
       RETURN FALSE;
    when UTL_FILE.INVALID_PATH then
         O_error_message := sql_lib.create_msg ('SMR_E3_PATH',
                                              l_path,
                                              L_extract_filename);
       RETURN FALSE;
    when OTHERS then
       O_error_message := sql_lib.create_msg ('PACKAGE_ERROR',
                                               SQLERRM,
                                              'SMR_E3_LED_TIME');
        RETURN FALSE;

END SMR_E3_LED_TIME_SQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

END SMR_E3_EXTRACT_SQL;
/