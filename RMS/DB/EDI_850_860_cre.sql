Drop table SMR_PO_EDI_850_860_HDR_EXP;
Create table SMR_PO_EDI_850_860_HDR_EXP (
        GROUP_ID                VARCHAR2(80),
        RECORD_ID               NUMBER(10),
/*H1*/	REC_TYPE1          	VARCHAR2(6),	/*recTypeDescH1*/
    	REC_TYPE2            	VARCHAR2(2),	/*'H'*/
    	REC_SEQ              	NUMBER(4),	/*recSequence*/
    	SUPPLIER_NMBR        	NUMBER(9),	/*supplier*/
    	COMPANY_ID           	NUMBER(3),	/*1*/
    	PO_TYPE              	VARCHAR2(2),	/*poType*/
    	PO_NMBR              	NUMBER(9),	/*order_no*/
    	PO_PURPOSE_CODE      	VARCHAR2(2),	/*poPurposeCode*/
    	DC_STORE_NMBR        	NUMBER(5),	/*dcStoreNumber*/
    	MASTER_PO_NMBR         	NUMBER(9),	/*masterorder_no*/
    	VENDOR_NMBR_REF      	VARCHAR2(2),	/*'IA'*/
    	VENDOR_NMBR          	NUMBER(9),	/*supplier*/
    	DEPT_NMBR_REF        	VARCHAR2(2),	/*'DP'*/
    	DEPT_NMBR            	NUMBER(3),	/*orderDept*/
    	BUYER_NMBR_REF       	VARCHAR2(2),	/*'BY'*/
    	BUYER_FNCTN_CODE     	VARCHAR2(2),	/*'BD'*/
    	BUYER_NMBR           	NUMBER(3),	/*buyer*/
    	BUYER_CONTACT_NAME   	VARCHAR2(60),	/*buyerName*/
    	BUYER_COMM_QUALFR    	VARCHAR2(2),	/*'TE'*/
    	BUYER_PHONE_NMBR     	VARCHAR2(80),	/*buyerPhone*/
    	DC_FUNCTION_CODE     	VARCHAR2(2),	/*'DC'*/
    	DC_CONTACT_NAME      	VARCHAR2(60),	/*null*/
    	DC_COMM_QUALIFER     	VARCHAR2(2),	/*'TE'*/
    	DC_PHONE_NMBR        	VARCHAR2(80),	/*null*/
    	CASH_REQ_CODE1        	VARCHAR2(2),	/*'NS'*/
    	CASH_REQ_CODE2        	VARCHAR2(2),	/*'SC'*/
    	DELIVERY_INSTRUCT    	VARCHAR2(35),	/*null*/
    	SPECIAL_FREIGHT_DESC 	VARCHAR2(20),	/*null*/
    	DISCOUNT_DESC        	VARCHAR2(30),	/*termsCode*/
    	TOTAL_QTY_PO     	NUMBER(9),	/*orderTotalQty*/               /* used to be TOTAL_850_QTY_PO     */
    	PO_APPROVE_DATE        	VARCHAR2(8),	/*originalApproveDate*/		/* changed to varchar(8) from date */
    	PO_REQUESTED_SHIP    	VARCHAR2(3),	/*'010'*/
    	PO_SHIP_DATE         	VARCHAR2(8),	/*newNotBeforeDate*/		/* changed to varchar(8) from date */
    	PO_RCV_DATE          	VARCHAR2(8),	/*'00000000'*/
    	PO_CANCEL_AFTER      	VARCHAR2(3),	/*'001'*/
    	PO_CANCEL_DATE       	VARCHAR2(8),	/*newNotAfterDate*/		/* changed to varchar(8) from date */
    	PO_CHANGE_DATE          VARCHAR2(8),	/*orderChangeDate*/             /* 860 only */
    	PO_PROMO             	VARCHAR2(3),	/*promoQualifier*/
    	PO_PROMO_DATE        	VARCHAR2(8),	/*promoStartDate*/
    	TERMS_ID_QUALIFER    	VARCHAR2(2),	/*'ME'*/
    	TERMS_OF_PURCH1    	VARCHAR2(170),	/*SMR_TERMS1*/
    	TERMS_OF_PURCH2    	VARCHAR2(170),	/*SMR_TERMS2 */
/*H2*/	CHARGE_IND           	VARCHAR2(1),	/*'N'*/
    	VICS                 	VARCHAR2(2),	/*'VI'*/
    	NEW_STORE_RUSH       	VARCHAR2(10),	/*sacCode*/
    	SAC_DESC             	VARCHAR2(40),	/*sacDesc */
/*H3*/	DESC_TYPE            	VARCHAR2(1),	/*'F'*/
    	SPLIT_COMMENTS       	VARCHAR2(50),	/*poHeaderComments*/
/*H4*/	SHIP_TO_MARK_FOR     	VARCHAR2(2),	/*shipToMarkFor*/
    	ADDRESS1              	VARCHAR2(55),	/*null*/
    	ADDRESS2              	VARCHAR2(55),	/*null*/
    	CITY                 	VARCHAR2(30),	/*null*/
    	STATE                	VARCHAR2(2),	/*null*/
    	ZIP                  	VARCHAR2(10),	/*null*/
    	COUNTRY              	VARCHAR2(3),	/*null*/
    	WH_DESC              	VARCHAR2(25),	/*h4WhName*/
    	CREATE_DATETIME         DATE)
/


Drop table SMR_PO_EDI_850_860_DTL_EXP;
Create table SMR_PO_EDI_850_860_DTL_EXP (
        GROUP_ID                VARCHAR2(80),
        RECORD_ID               NUMBER(10),
/*D1*/	REC_TYPE1          	VARCHAR2(6),	/*recTypeDescD1*/	
	REC_TYPE2            	VARCHAR2(2),	/*'D'*/
	REC_SEQ              	NUMBER(4),	/*d1RecSequence*/
	SUPPLIER_NMBR        	NUMBER(9),	/*supplier*/
	COMPANY_ID           	NUMBER(3),	/*1*/
	PO_NMBR              	NUMBER(9),	/*order_no*/
	DC_STORE_NMBR        	NUMBER(5),	/*dcStoreNumber*/
	ITEM_SKU_NMBR        	NUMBER(11),	/*item*/
	ITEM_STORE_NMBR      	NUMBER(9),	/*0*/
	DETAIL_REC_SUB_SEL   	NUMBER(5),	/*1*/
	PO_CHANGE_CODE          VARCHAR2(2),    /*ordItemLocChangeCode*/   /* 860 only */
	VPN                  	VARCHAR2(15),	/*itemSupVPN*/
	ITEM_QTY             	NUMBER(7),	/*qtyOrdered*/
        QTY_LEFT_TO_RECEIVE     VARCHAR2(7),    /*qtyDiffOrdered*/         /* 860 only */
        UNIT_COST            	NUMBER(10),	/*orderUnitCost*/
	UPC                  	VARCHAR2(15),	/*upc*/
	RETAIL_PRICE_ID      	VARCHAR2(3),	/*'MSR'*/
	RETAIL_PRICE         	NUMBER(10),	/*orderUnitRetail*/
	BUYER_COLOR_QUALIFIER	VARCHAR2(2),	/*'BO'*/
	BUYER_COLOR_DESC     	VARCHAR2(15),	/*itemColorDesc*/
	BUYER_SIZE_QUALIFIER 	VARCHAR2(2),	/*'IZ'*/
	BUYER_SIZE_DESC      	VARCHAR2(15),	/*itemSizeDesc*/
	COMPARE_TO_PRICE_ID  	VARCHAR2(3),	/*'MSR'*/
	COMPARE_TO_PRICE     	NUMBER(10),	/*itemMfgRecRetail*/
/*D2*/	CHARGE_IND           	VARCHAR2(1),	/*'N'*/
	VICS                 	VARCHAR2(2),	/*'VI'*/
	TCKT_HANG_CODE         	VARCHAR2(10),	/*itemTicketTypeId	D2 item_ticket or D2 hanger type*/
	TCKT_HANG_DESC        	VARCHAR2(80),	/*itemTicketTypeDesc	D2 item_ticket or D2 hanger type*/
/*D3*/  STORE			VARCHAR2(5),   
	STORE_QUANTITY		NUMBER(7),
	SDQ_TEXT                VARCHAR2(3),	
	SDQ1_STORE		VARCHAR2(5),   
	SDQ1_STORE_QUANTITY	NUMBER(7),      
	SDQ2_STORE		VARCHAR2(5),   
	SDQ2_STORE_QUANTITY	NUMBER(7),      
	SDQ3_STORE		VARCHAR2(5),   
	SDQ3_STORE_QUANTITY	NUMBER(7),      
	SDQ4_STORE		VARCHAR2(5),   
	SDQ4_STORE_QUANTITY	NUMBER(7),      
	SDQ5_STORE		VARCHAR2(5),   
	SDQ5_STORE_QUANTITY	NUMBER(7),      
	SDQ6_STORE		VARCHAR2(5),   
	SDQ6_STORE_QUANTITY	NUMBER(7),      
	SDQ7_STORE		VARCHAR2(5),   
	SDQ7_STORE_QUANTITY	NUMBER(7),      
	SDQ8_STORE		VARCHAR2(5),   
	SDQ8_STORE_QUANTITY	NUMBER(7),      
/*D4*/	ITEM_QUANTITY		NUMBER(7),   
	UOM_IDENTIFIER		VARCHAR2(2),
	GROSS_UNIT_COST		NUMBER(10),
/*VP*/	PACK_SKU_NMBR        	NUMBER(11),	
	PACK_UNITS		NUMBER(8),
	PACK_UNIT_COST		NUMBER(10),
	PACK_UPC		VARCHAR2(15),
	TOTAL_SUBLINE_QTY	NUMBER(9),
    	CREATE_DATETIME         DATE)
/

create index SMR_PO_EDI_850_860_i1 on SMR_PO_EDI_850_860_HDR_EXP(PO_NMBR);
create index SMR_PO_EDI_850_860_i2 on SMR_PO_EDI_850_860_DTL_EXP(REC_TYPE1,PO_NMBR,ITEM_SKU_NMBR,REC_SEQ);

insert into restart_control(PROGRAM_NAME,
PROGRAM_DESC,
DRIVER_NAME,
NUM_THREADS,
UPDATE_ALLOWED,
PROCESS_FLAG,
COMMIT_MAX_CTR) (select 'smr_edi850sdq',
PROGRAM_DESC,
DRIVER_NAME,
NUM_THREADS,
UPDATE_ALLOWED,
PROCESS_FLAG,
COMMIT_MAX_CTR from restart_control where program_name = 'smr_edi850dl');

insert into restart_program_status(RESTART_NAME,
THREAD_VAL,
START_TIME,
PROGRAM_NAME,
PROGRAM_STATUS,
RESTART_FLAG,
RESTART_TIME,
FINISH_TIME,
CURRENT_PID,
CURRENT_OPERATOR_ID,
ERR_MESSAGE,
CURRENT_ORACLE_SID,
CURRENT_SHADOW_PID) (select 'smr_edi850sdq',
THREAD_VAL,
START_TIME,
'smr_edi850sdq',
PROGRAM_STATUS,
RESTART_FLAG,
RESTART_TIME,
FINISH_TIME,
CURRENT_PID,
CURRENT_OPERATOR_ID,
ERR_MESSAGE,
CURRENT_ORACLE_SID,
CURRENT_SHADOW_PID from restart_program_status where restart_name = 'smr_edi850dl');

alter table OLR_SMR_ORD_EXTRACT_117633  modify  (order_no number(10)); /*860_cleanup*/

drop public synonym SMR_PO_EDI_850_860_HDR_EXP;   
create public synonym SMR_PO_EDI_850_860_HDR_EXP for RMS13.SMR_PO_EDI_850_860_HDR_EXP;
grant select,insert,update on SMR_PO_EDI_850_860_HDR_EXP to DEVELOPER,RMS13_SELECT;
GRANT  INSERT, UPDATE ON SMR_PO_EDI_850_860_HDR_EXP TO SVC_INT_RMS;

drop public synonym SMR_PO_EDI_850_860_DTL_EXP;   
create public synonym SMR_PO_EDI_850_860_DTL_EXP for RMS13.SMR_PO_EDI_850_860_DTL_EXP;
grant select,insert,update on SMR_PO_EDI_850_860_DTL_EXP to DEVELOPER,RMS13_SELECT;
GRANT  INSERT, UPDATE ON SMR_PO_EDI_850_860_DTL_EXP TO SVC_INT_RMS;

drop sequence "RMS13"."RMS_SMR_EDI_850_860_SEQ";
CREATE SEQUENCE  "RMS13"."RMS_SMR_EDI_850_860_SEQ"  MINVALUE 1 MAXVALUE 999999999 INCREMENT BY 1 START WITH 1 CACHE 100 NOORDER CYCLE ;


