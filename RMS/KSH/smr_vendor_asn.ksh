#!/bin/ksh

#**********************************************************************
#  Program Name: smr_vendor_asn.ksh
#  Author:       Murali N
#  Date:         23-Jun-2015
#
#  MODIFICATION HISTORY
#  Ver.  Person      Date        Issue    Comments
#  ----  ----------- ----------- -------- -----------------------------
#  1.0   Murali N   23-Jun-15   Leap     Initial version.
#
#  Description:
#    The purpose of this batch program is to load the ASN files .
# This script will be the main script that is invoked from the UC4 Job. This script will invoke the database 
# packages to process the ASN data loaded in the interface tables.
#    It calles Pl/Sql packaged function
#    SMR_VENDOR_ASN_SQL.F_PROCESS_VEND_ASN
#
#  Restart/Recovery:
#    If this program aborts, correct the error and rerun the ksh program.
#    Make sure to remove any ASN*.dat files in MMIN and leave only the smrediasn_*.tar.gz files
#
#  Usage:  Usage: smr_vendor_asn.ksh [tar file date]
#
#  Issue Resolution:
#
#*********************************************************************/

#############################################################################################
#VARIABLE DECLARATION
#############################################################################################
typeset -r dbConnect="$MMUSER/$PASSWORD@$ORACLE_SID"

file_folder="$MMIN"
l_tar_date=`date +%Y%m%d%H%M%S`
extract_file="smrvndasn_*.tar.gz"
temp_file="/tmp/err_smr_vendor_asn.${l_tar_date}"
l_control_file="/tmp/err_smr_vendor_asn.ctl"
l_control_log_file="/tmp/err_smr_vendor_asn.log"
l_error_file="$MMHOME/error/err_smr_vendor_asn.${l_tar_date}"
#############################################################################################
#FUNCTION DECLARATION
#############################################################################################

f_remove_input_file(){

   f_log "Cleaning up input file ${1}"
   rm ${1} 2>/dev/null
   if [ -f ${1} ]; then
      f_error "Failed to remove input file ${1}, Please remove it manually"
   fi

}

f_remove_file(){

   f_log "Cleaning up file ${1}"
   rm ${1} 2>/dev/null
   if [ -f ${1} ]; then
      f_log "Failed to remove input file ${1}, Please remove it manually"
   fi

}

f_error(){
   echo "${1}" >> ${l_error_file}
   f_remove_temp_files
   f_log "Aborted in process"
   exit 1
}

f_error_mulitple(){

   if [ ! -f ${1} ]; then
      f_error "Could not find error file ${1}"
   fi
   cat "${1}" >> ${l_error_file}
   f_remove_file ${1}
   f_remove_temp_files
   f_log "Aborted in process"
   exit 1

}

f_log(){
   l_log=`date +%b`_`date +%d`.log
   if [ ! -f $MMHOME/log/${l_log} ]; then
      touch $MMHOME/log/${l_log}
      chmod 666 $MMHOME/log/${l_log}
      if [ ! -f $MMHOME/log/${l_log} ]; then
         #Don't call f_error here, otherwise we will go into an infinite loop
         echo "Failed to create log file $MMHOME/log/${l_log}" >> ${l_error_file}
         exit 1

      fi
   fi

   l_log_line=`date | cut -d"E" -f1`
   l_log_line="${l_log_line} Program: `basename ${0}`: PID=$$ Thread 1 - ${1}"
   echo ${l_log_line} >> $MMHOME/log/${l_log}

}

f_remove_temp_files(){

   f_log "Cleaning up temp files..."

   rm ${temp_file} 2>/dev/null
   if [ -f ${temp_file} ]; then
      f_log "Failed to remove temp file ${temp_file}, Please remove it manually"
   fi

   rm ${l_control_file} 2>/dev/null
   if [ -f ${l_control_file} ]; then
      f_log "Failed to remove control file ${l_control_file}, Please remove it manually"
   fi

   rm ${l_control_log_file} 2>/dev/null
   if [ -f ${l_control_log_file} ]; then
      f_log "Failed to remove control log file ${l_control_log_file}, Please remove it manually"
   fi

}

f_process_file()
{
   plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   whenever sqlerror exit 1 rollback
   set serveroutput on size 100000
   set feedback off

   DECLARE

      L_error_message VARCHAR2(255);
      L_file_errors   NUMBER(10,0);
      L_file_failed   BOOLEAN := false;
      L_now           DATE := SYSDATE;
      L_input_file    VARCHAR2(255) := '${1}';

      FUNC_ERROR      EXCEPTION;

   BEGIN

     IF SMR_VENDOR_ASN_SQL.F_PROCESS_VEND_ASN(L_error_message,
											  L_file_errors,
											  L_file_failed)= false then

        dbms_output.put_line('Aborted in process');
        raise FUNC_ERROR;

     ELSE

        IF L_file_failed then
           dbms_output.put_line('Terminated with file failure');
        ELSIF nvl(L_file_errors,0) > 0 then
           dbms_output.put_line('Terminated with file errors');
        ELSE
           dbms_output.put_line('Terminated Successfully');
        END IF;

     END IF;

   EXCEPTION
      WHEN FUNC_ERROR then
         dbms_output.put_line(L_error_message);
         ROLLBACK;
      when OTHERS then
         L_error_message :=  TO_CHAR(SQLCODE) || SQLERRM ||'-'|| L_error_message;
         dbms_output.put_line(L_error_message);
         ROLLBACK;
   END;
/

ENDSQL`

echo "${plsql_result}"

}

f_process_error_file()
{
   plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   set trimspool on
   set lines 1000
   set pages 0
   set feedback off

   spool $MMOUT/asnerror_${l_tar_date}.dat

   SELECT DISTINCT
          NVL( LPAD(partner,9,'0'), '000000000') ||
          NVL( RPAD(asn   ,30,' '), '                              ') ||
          '          ' ||
          LPAD(error_code,3,'0') ||
          error_type ||
          RPAD(nvl(error_value,' '),50,' ') ||
          to_char(fail_date,'YYYYMMDDHH24MISS') ||
          '0000000000000000000000000000'
     FROM smr_asn_vendor_errors
    ORDER BY 1;

   spool off

ENDSQL`

}

f_process_noerror_file()
{
   plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   set trimspool on
   set lines 1000
   set pages 0
   set feedback off

   spool $MMOUT/asnnoerr_${l_tar_date}.dat

   SELECT distinct
          LPAD(partner,              9,'0') ||
          RPAD(asn,                 30,' ') ||
          RPAD(decode(pack_sku,null,' ',CARTON), 48,' ') ||
          LPAD(nvl(pack_sku,'0'),   11,'0') ||
          LPAD(nvl(sku,'0'),        11,'0') ||
          LPAD(nvl(qty_shipped,'0'), 8,'0')
     FROM smr_856_vendor_successful
     ORDER BY 1;

   spool off

ENDSQL`

}

f_gather_stats_smr_856_vendor_item()
{
   plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   set feedback on
   begin
   DBMS_STATS.GATHER_TABLE_STATS(OWNNAME => 'RMS13', TABNAME => 'SMR_856_VENDOR_ITEM',
     METHOD_OPT => 'FOR ALL COLUMNS SIZE AUTO', BLOCK_SAMPLE => true, GRANULARITY => 'ALL',
     cascade => true, NO_INVALIDATE => false, degree => 4);
   end;
   /

ENDSQL`

echo "${plsql_result}"

}

f_clean_error_table()
{
   plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   set feedback on

   TRUNCATE TABLE smr_asn_vendor_errors;

ENDSQL`

echo "${plsql_result}"

}

f_clean_success_table()
{
   plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   set feedback on

   TRUNCATE TABLE smr_856_vendor_successful;

ENDSQL`

echo "${plsql_result}"

}

f_load_file(){

   f_log "Creating control file for ${1}"

   l_file_type=`basename ${input_file} | cut -d"_" -f1 | cut -c4-`

   if [ -f ${l_control_file} ]; then
      echo "Failed to remove control file ${l_control_file}" >${temp_file}
      rm ${l_control_file} 2>>${temp_file}
      if [ -f ${l_control_file} ]; then
         f_error_mulitple "${temp_file}"
      else
         echo "" > ${temp_file}
      fi
   fi

   echo "Failed to create control file ${l_control_file}" >${temp_file}
   touch ${l_control_file} 2>>${temp_file}
   if [ ! -f ${l_control_file} ]; then
      f_error_mulitple "${temp_file}"
   else
      echo "" > ${temp_file}
   fi

   echo "load data" > ${l_control_file}
   echo "infile '${1}'" >> ${l_control_file}
   echo "replace" >> ${l_control_file}
   if [ "${l_file_type}" = "SHIP" ]; then
      echo "into table SMR_856_VENDOR_ASN " >> ${l_control_file}

      echo '(  partner      position (  1 :  9 ),
               asn          position ( 16 : 45 ) "rtrim(ltrim(:asn))",
               vendor       position (  1 :  9 ),
               bol_no       position (350 :379 ) "rtrim(ltrim(:bol_no))",
               ship_date    position (533 :540 ) "to_date(:ship_date,'"'YYYYMMDD')"'",
               est_arr_date POSITION (550 :557 ) "to_date(decode(:est_arr_date,0,null,:est_arr_date),'"'YYYYMMDD')"'",
               ship_to      position (629 :708 ),
               courier      position (132 :211 ) "rtrim(ltrim(:courier))"
            )' >> ${l_control_file}

   elif [ "${l_file_type}" = "ORDER" ]; then
      echo "into table SMR_856_VENDOR_ORDER" >> ${l_control_file}

      echo '( partner     position (  1:  9 ),
              ASN         position ( 16: 45) "rtrim(ltrim(:asn))",
              order_no    position ( 46: 51),
              order_loc   position ( 52: 54),
              vendor      position (153:161),
              mark_for    position (232:311)
             )' >> ${l_control_file}

   elif [ "${l_file_type}" = "ITEM" ]; then
      echo "into table SMR_856_VENDOR_ITEM" >> ${l_control_file}

     echo '(  partner       position (  1:  9),
              ASN           position ( 16: 45) "rtrim(ltrim(:asn))",
              vendor        position (  1: 9 ),
              order_no      position ( 46: 51),
              order_loc     position ( 52: 54),
              carton        position ( 79:126) "rtrim(ltrim(:carton))",
              Upc           position (129:141) "decode(:upc,'"'0000000000000'"',null,:upc)",
              Sku           position (144:154) "rtrim(ltrim(:sku))",
              Units_shipped position (172:179),
			  mark_for      position (301:380) "rtrim(ltrim(:mark_for))"
           )' >> ${l_control_file}

   else
      f_error "Invalid file type: ${l_file_type}"
   fi

      f_log "Running control file for ${1}"

      sqlldr $dbConnect control=${l_control_file} log=${l_control_log_file} 1>/dev/null
      if [ ${?} -ne 0 ]; then
        f_error "failed SQL loading"
      fi

}

#############################################################################################
#start program
#############################################################################################
f_log "Started"

#############################################################################################
#PRE CHECKS
#############################################################################################

#Check at least one input file exists. This script should only run if there is an input file to process
if [ ! -f ${file_folder}/${extract_file} ]; then
   f_log "No valid extract file found like ${file_folder}/${extract_file}"
   f_log "Terminated Successfully"
   exit 0
fi

#############################################################################################
#SETUP
#############################################################################################

#Create temp file
touch ${temp_file}
if [ ${?} -ne 0 ]; then
  f_error "Failed to create temp file ${temp_file}"
fi


#############################################################################################
#MAIN PROCESSING
#############################################################################################

# For Each file set
for file_zip in `ls ${file_folder}/${extract_file}`
do

   l_datetime=`basename ${file_zip} | cut -c12-25`

   #Clean out old files
   f_log "Check for old files in ${file_folder}/"

   if [  -f ${file_folder}/ASNSHIP*  ] ; then
      f_error "OLD ASN shipment files file exists. "
   fi

   if [  -f ${file_folder}/ASNORDER_* ] ; then
      f_error "OLD ASN order files file exists. "
   fi

   if [  -f ${file_folder}/ASNITEM_* ] ; then
      f_error "OLD ASN item files file exists. "
   fi

   #Extract zip (use unzip as file was created by PKZIP)
   f_log "unzip ${file_zip}"
   unzip -d ${file_folder} ${file_zip} 1>${temp_file} 2>${temp_file}
   if [  $? -gt 3 ]; then
      f_error "Error unzipping ${file_zip} : `cat ${temp_file}`"
   else

      echo "" > ${temp_file}

      #Check that extract containes 3 files
      if [  -f ${file_folder}/ASN*  ] ; then
         file_found=`ls -l ${file_folder}/ASN*.dat | wc -l`
         file_found=`expr ${file_found} + 0`
         if [ "${file_found}" -ne "3" ]; then
            f_error "Extract contains ${file_found} files, 3 files expected."
         fi
      else
         f_error "Extract contains no valid files"
      fi

   fi

   for input_file in `ls ${file_folder}/ASN*.dat `
   do
     chmod 777 ${input_file}

     f_load_file ${input_file}

     f_remove_input_file ${input_file}
   done

   f_log "Gathering smr_856_vendor_item stats"
   result=`f_gather_stats_smr_856_vendor_item`

   if [ `echo ${result} | grep "PL/SQL procedure successfully completed." | wc -l` -ne 1 ] ; then
      f_error "Error Gathering smr_856_vendor_item stats: ${result}"
   fi

   f_log "Process file ${file_zip}"

   result=`f_process_file ${l_datetime}`

   f_remove_temp_files

   l_result_ok="no"

   if [ `echo $result | grep "Terminated Successfully" | wc -l` -gt 0 ] ; then
      f_log "File ${file_zip} Finished OK"
      l_result_ok="yes"
   fi

   if [ `echo $result | grep "Terminated with file errors" | wc -l` -gt 0 ] ; then
      f_log "File ${file_zip} Finished OK with errors"
      l_result_ok="yes"
   fi

   if [ `echo $result | grep "Terminated with file failure" | wc -l` -gt 0 ] ; then
      f_log "File ${file_zip} rejected"
      l_result_ok="yes"
   fi

   if [ "${l_result_ok}" = "no" ] ; then
      f_error "Error processing ${file_zip}: ${result}"
   fi

   #archive file after processing.
   l_archive_date=`date +%Y%m%d`
   if [ ! -d $MMIN/archive/${l_archive_date} ]; then
      mkdir $MMIN/archive/${l_archive_date}
      chmod 777 $MMIN/archive/${l_archive_date}
   fi
   mv ${file_zip} $MMIN/archive/${l_archive_date}

done

   f_log "Doing spool file:Errors"

   f_process_error_file

   if [ ! -f $MMOUT/asnerror_${l_tar_date}.dat  ]; then
      f_error "Error creating error spool file $MMOUT/asnerror_${l_tar_date}.dat"
   fi

   f_log "Doing spool file:NoErrors"

   f_process_noerror_file

   if [ ! -f $MMOUT/asnnoerr_${l_tar_date}.dat  ]; then
      f_error "Error creating success spool file $MMOUT/asnnoerr_${l_tar_date}.dat"
   fi

   f_log "Cleaning error table"
   result=`f_clean_error_table`
 
   if [ `echo ${result} | grep "Table truncated." | wc -l` -ne 1 ] ; then
      f_error "Error truncating error table: ${result}"
   fi
 
   f_log "Cleaning success table"
   result=`f_clean_success_table`
 
   if [ `echo ${result} | grep "Table truncated." | wc -l` -ne 1 ] ; then
      f_error "Error truncating success table: ${result}"
   fi
 
   f_log "Terminated Successfully"
 
exit 0

