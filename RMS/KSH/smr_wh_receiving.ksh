#!/bin/ksh
#-------------------------------------------------------------------------
#  File:  smr_wh_receiving.ksh

#  Desc:  UNIX shell script to extract to Process WH receipts from WA
#-------------------------------------------------------------------------
#############################################################################
# Modification History
# Ver. Date        Programmer         Description
# ==== =========== ================   =============
# 1.00 10-May-15   Murali Natarajan   Process the Wh reciepts from Interface table into RMS      
#This is the main script that used to process the Warehouse receiving data into RMS . 
#1.	The script is invoked from the UC4 .
#2.	Invoke the package SMR_WH_RECEIVING.F_PROCESS_RECEIPTS to process the receiving data from Interface tables.
#3.	In case of any unhandled Exception or Oracle Error returned by the Invoked procedure the scripts aborts and writes the Error to the error log.
#4.	Upon successful completion of the database procedure the script writes to the log and returns successful completion to UC4.

#############################################################################
# Revision : $Id: 

#############################################################################################
#VARIABLE DECLARATION
#############################################################################################
typeset -r dbConnect="$MMUSER/$PASSWORD@$ORACLE_SID"

run_function()
{

plsql_result=`sqlplus -s $dbConnect <<-ENDSQL 
   whenever sqlerror exit 1
   set serveroutput on
      set heading off
      set verify off
      set feedback off
   
   VARIABLE outtext VARCHAR2(4000)

   DECLARE
      L_error_message varchar2(500):= NULL;
   BEGIN

	  if  SMR_WH_RECEIVING.F_PROCESS_RECEIPTS(l_ERROR_MESSAGE ) = FALSE then
		 raise_application_error(-20010, l_error_message);
	  else
		 L_error_message := '';
	  end if;
	  
	  commit;
  EXCEPTION
   when OTHERS then
      L_error_message := SQLERRM || l_error_message  || TO_CHAR(SQLCODE);
      :outtext := L_error_message;
     rollback;
  END;
/
 print :outtext
  QUIT;
ENDSQL`

    echo " plsql result $plsql_result"

#	if [[ "${plsql_result}" = +(*"ORA-"*) ]]; then
	if [ `echo ${plsql_result} | grep "ORA-"  | wc -l` -gt 0 ] ;  then
	 logdate=`date +"%a %h %d %T"`
	 echo "$logdate Program: ${0}: Error while running package c$plsql_result  $1  ..." >> $MMHOME/error/$errfile
	  return 1
	else
	  return 0
	fi
}

# Main Program

logdate=`date +"%a %h %d %T"`
logfile=`date +"%h_%d.log"`
errfile="err.smr_wh_receiving.`date +"%h_%d"`"

echo "$logdate Program: ${0}: Started" >> $MMHOME/log/$logfile
	   
run_function

if [ $? -eq 0 ]
then
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Terminated Succesfully " >> $MMHOME/log/$logfile
else
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Terminated with errors " >> $MMHOME/log/$logfile
   exit 1 
fi

exit 0


