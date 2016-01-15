set pages 0
set termout off
set verify off
set feedback off
set echo off
set lines 1000
set trims on
set time off
set timing off
spool &1.dat
select EDI850 from v_smr_write_edi850 order by group_id,record_id;
spool off;
set pages 5000
set termout on
set echo on
set feedback on
set verify on
set lines 80
set trims off
set time on
set timing on

