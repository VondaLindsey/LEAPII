#!/bin/ksh


echo " userpass $1 " 

echo " UP $UP "
echo " file is $2 "

echo " args $#"
# Parse the command line
#-----------------------------------------------
if [ $# -lt 2 ] ; then
   echo "Usage: $0 User/pass InFile "
   exit 1
fi

echo " userpass $1 " 

echo " UP $UP "

 UP=$UP
 INFILE=$2
LOG_DATE="$(date '+%Y%m%d')"

export SQLHOME=/app/oracle/product/11.2.0.3/dbms/bin/
export CONNECT_STRING=$UP
LDR_FILE=SmrEdi810_FileLoad.ctl
BASEDIR=$(dirname $0)
batch_log=${BASEDIR}
LOG_DIR=${BASEDIR}/../log
ERR_DIR=${BASEDIR}/../log
CTLFILE=${BASEDIR}/SmrEdi810_FileLoad.ctl
ERR_FILE=${ERR_DIR}/err.`basename $0`.${LOG_DATE}

echo $CONNECT_STRING

. ${BASEDIR}/smr_leap2_lib.ksh


rm -f ${ERR_FILE}

function TRUNCATE_STG_TABLES {
   sqlplus -s ${UP} <<EOF > ${ERR_FILE}
      set echo off;
      set feedback off;
      set heading off;
      set verify off;
      set termout off;
      VARIABLE GV_script_error VARCHAR2(100);
   
      DECLARE
         L_owner VARCHAR2(30) := NULL;
      BEGIN
   
         execute immediate 'Truncate table rms13.SMR_RMS_INT_EDI_810_HDR_STG';
         execute immediate 'Truncate table rms13.SMR_RMS_INT_EDI_810_DTL_STG';
      EXCEPTION
         when OTHERS then
            :GV_script_error := SQLERRM;
      end;
      /
EOF

   if [ `grep "ORA-" ${ERR_FILE} | wc -l` -gt 0 ]
   then
      dtStamp=`date +"%a %b %e %T"`
      echo "${dtStamp} ORA Error while Truncating tables SMR_RMS_INT_EDI_810_HDR/DTL/STG" >> ${ERR_FILE}
      return 1
   fi
echo " before success truncate"
  return 0
}

function LOAD_STG_DATA {
   sqlTxt="
      DECLARE
     
         L_error_message      varchar2(255);
     
 BEGIN
 
     if SMR_RMS_INT_EDI_810.EDI810_PRE (L_error_message ) = FALSE then
          dbms_output.put_line(L_error_message);
         :GV_return_code  := ${FATAL};
    end if;
   
 
            :GV_return_code := ${OK};
          commit;
      EXCEPTION
         WHEN OTHERS THEN
             dbms_output.put_line(SQLERRM);
             :GV_return_code  := ${FATAL};
             RAISE;
      END;"

   result=$(EXEC_SQL ${sqlTxt})

   err=$?

   if [[ $err -eq ${NONFATAL} ]] ; then
      echo $result
      LOG_ERROR "$result" "LOAD_STG_DATA" ${NONFATAL}
      return $err
   fi

   if [[ $err -ne ${OK} ]] ; then
      echo $result
      LOG_ERROR "$result" "LOAD_STG_DATA" ${NONFATAL}
      return $err
   fi

   LOG_ERROR "$result" "LOAD_STG_DATA" ${OK}

   return 0

}
#### Execution starts from here
# Main program starts
rm -f  ${LOG_DIR}/${LDR_FILE}.log
#######################################################################
# If this script is killed, cleanup
trap "kill -15 0; rm -f $failed; exit 15" 1 2 3 15

failed=${pgmName}.$$
[ -f ${failed} ] && rm ${failed}
# Step 1

TRUNCATE_STG_TABLES
if [[ $? -gt 0 ]] ; then
   dtStamp=`date +"%a %b %e %T"`
   LOG_ERROR "${dtStamp} Error From TRUNCATE_STG_TABLES SMR_RMS_INT_EDI_810_HDR/DTL/STG" 
   return 1
fi

echo "Step 2"

  sqlldr ${UP} silent=feedback,header control=${CTLFILE} log=${LOG_DIR}/${LDR_FILE}.log data=${INFILE} bad=${ERR_DIR}/${LDR_FILE}.bad discard=${ERR_DIR}/${LDR_FILE}.dsc
   if [ ${?} -ne 0 ]; then
      LOG_ERROR  "Failed SQL loading. Check SQL Loader log file: ${LOG_DIR}/${LDR_FILE}.log"
   fi

echo "Step 3"

LOAD_STG_DATA
if [[ $? -gt 0 ]] ; then
   dtStamp=`date +"%a %b %e %T"`
   LOG_ERROR "${dtStamp} Error From TRUNCATE_STG_TABLES SMR_RMS_INT_EDI_810_HDR/DTL/STG" 
   return 1
fi


exit 0
