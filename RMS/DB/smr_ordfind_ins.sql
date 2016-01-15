insert into nav_element values('smr_ordfind','F','RMS');
update NAV_ELEMENT_MODE_ROLE_RESACLK set element = 'smr_ordfind' where element = 'ordfind';
insert into NAV_ELEMENT_MODE (select 
'smr_ordfind',                
NAV_MODE               ,
FOLDER                 ,
ELEMENT_MODE_NAME      ,
USER_ID                ,
FINANCIAL_O_IND        ,
FINANCIAL_P_IND        ,
FINANCIAL_NULL_IND,
CONTRACT_IND           ,
VAT_IND                ,
IMPORT_IND             ,
MULTICHANNEL_IND      from NAV_ELEMENT_MODE where element = 'ordfind');

update NAV_ELEMENT_MODE_ROLE set element = 'smr_ordfind' where element = 'ordfind';
update NAV_ELEMENT_MODE_BASE set element = 'smr_ordfind' where element = 'ordfind';
update NAV_FAVORITES set favorite_id = 'smr_ordfind' where favorite_id = 'ordfind';

delete from  NAV_ELEMENT_MODE where element = 'ordfind';
delete from NAV_ELEMENT where element = 'ordfind';

--update NAV_ICON set filename = 'smr_ordfind' where filename = 'ordfind';

/**
    LD_LIBRARY_PATH=$ORACLE_HOME/lib:$ORACLE_HOME/jdk/jre/lib/i386/server:$ORACLE_HOME/jdk/jre/lib/i386/native_threads:$ORACLE_HOME/jdk/jre/lib/i386:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH
**/
