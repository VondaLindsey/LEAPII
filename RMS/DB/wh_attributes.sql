insert into code_head values('WHTC','Warehouse Type Code (used in wh_attributes)');
insert into code_detail values('WHTC','PA','Put-away','Y',1);
insert into code_detail values('WHTC','XD','x-dock','Y',2);
insert into code_detail values('WHTC','DD','Direct Delivery','Y',3);

alter table wh_attributes add( WH_TYPE_CODE varchar2(4));

/*** syntax 
alter table wh_attributes add CONSTRAINT "WH_ATTR_CODE_DETAIL" CHECK (WH_TYPE_CODE IN (select code from code_detail where code='WHTC')) ENABLE;


WH	TOTAL_SQUARE_FT	NO_LOADING_DOCKS	NO_UNLOADING_DOCKS	UPS_DISTRICT	TIME_ZONE	WH_TYPE_CODE
9521				3		XD
9531				3		XD
9541				3		XD
9522				3		PA
9401				3		BK
9402				4		DD
901	1000			1		
972	1000			1		
9532				3		PA
9542				3		PA
****/

update wh_attributes set WH_TYPE_CODE = 'XD' where wh in (9521,9531,9541);
update wh_attributes set WH_TYPE_CODE = 'BK' where wh = 9401;
update wh_attributes set WH_TYPE_CODE = 'DD' where wh = 9402;
update wh_attributes set WH_TYPE_CODE = 'PA' where wh in (9522,9532,9542);

commit;
