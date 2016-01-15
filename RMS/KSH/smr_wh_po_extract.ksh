#!/bin/ksh
#-------------------------------------------------------------------------
#  File:  smr_wh_po_extract.ksh
#
#  Desc:  UNIX shell script to extract WH PO data from SMR_RMS_WH_PO_DTL_STG  
#  and load the data into Interface Tables                  
#-------------------------------------------------------------------------
#############################################################################
# Modification History
# Ver. Date        Programmer         Description
# ==== =========== ================   =============
# 1.00 25-Aug-15   Steve Fehr         Fetch the WH PO's created in RMS from SMR_RMS_WH_PO_DTL_STG      
#                                     and populate the interface tables
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

	  if  SMR_LEAP_INTERFACE_SQL.WH_PO_EXTRACT(l_ERROR_MESSAGE ) = FALSE then
		 raise_application_error(-20010, l_error_message);
	  else
		 L_error_message := '';
	  end if;

  EXCEPTION
   when OTHERS then
      L_error_message := SQLERRM || l_error_message  || TO_CHAR(SQLCODE);
      :outtext := L_error_message;
  END;
/
 print :outtext
  QUIT;
ENDSQL`

    echo " plsql result $plsql_result"

	if [[ "${plsql_result}" = +(*"ORA-"*) ]]; then
	 logdate=`date +"%a %h %d %T"`
	 echo "$logdate Program: ${0}: Error while running package c$plsql_result  $1  ..." >> ${MMHOME}/error/$errfile
	  return 1
	else
	  return 0
	fi
}

# Main Program

logdate=`date +"%a %h %d %T"`
logfile=`date +"%h_%d.log"`
errfile="err.smr_wh_po_extract.`date +"%h_%d"`"

echo "$logdate Program: ${0}: Started" >> $MMHOME/log/$logfile
		   
run_function

if [ $? -eq 0 ]
then
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Terminated Succesfully " >> $MMHOME/log/$logfile
else
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Terminated with errors " >> $MMHOME/log/$logfile
fi

exit 0


