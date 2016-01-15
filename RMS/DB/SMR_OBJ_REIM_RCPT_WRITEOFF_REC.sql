CREATE OR REPLACE
TYPE         RMS13.OBJ_REIM_RCPT_WRITEOFF_REC                                          AS OBJECT
(
  shipment NUMBER(10),
  shipdate DATE,
  item VARCHAR2(25),
  unmatched_amt NUMBER(20,4),
  order_no NUMBER(10),
  location NUMBER(10),
  loc_type VARCHAR2(1)
)
/