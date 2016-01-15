
/*  COLUMN LENGTHS  */

#define LEN_ADDRESS                240  /* NLS */
#define LEN_ADDRESS_TYPE             2
#define LEN_ADJUST_TYPE              2
#define LEN_ALLOC_NO                10
#define LEN_ALLOC_TYPE               4
#define LEN_AMT                     20
#define LEN_APPLY_TO                 1
#define LEN_AREA                    10
#define LEN_BL_AWB_ID               30
#define LEN_BUYER                    4
#define LEN_BUY_TYPE                 1
#define LEN_CARTON                  20
#define LEN_CHAIN                   10
#define LEN_CHANGE_TYPE              2
#define LEN_CITY                   120  /* NLS */
#define LEN_CHANNEL_ID               4
#define LEN_CHANNEL_TYPE             6
#define LEN_CLASS                    4
#define LEN_CLASS_NAME             120  /* NLS */
#define LEN_CLEARANCE                8
#define LEN_CODE                     6
#define LEN_CODE_DESC               40
#define LEN_COMPANY                  4
#define LEN_COMP_NO                  4
#define LEN_CONTRACT_NO              6
#define LEN_COST_CHANGE              8
#define LEN_COUNTRY_ID               3
#define LEN_CURRENCY_CODE            3
#define LEN_CUSTOMER                10
#define LEN_CYCLE_COUNT              8
#define LEN_DATE                    14
#define LEN_DEPT                     4
#define LEN_DEPT_NAME              120  /* NLS */
#define LEN_DIFF_DESC              120  /* NLS */
#define LEN_DIFF_GROUP_ID           10
#define LEN_DIFF_ID                 10
#define LEN_DIFF_RANGE_ID           10
#define LEN_DISCOUNT_TYPE            1
#define LEN_DISPLAY_NO               8
#define LEN_DISTRICT                10
#define LEN_DISTRICT_NAME          120  /* NLS */
#define LEN_DIVISION                 4
#define LEN_DIV_NAME               120  /* NLS */
#define LEN_DOMAIN                   3
#define LEN_DOMAIN_ID                3
#define LEN_DUNS_NUMBER              9
#define LEN_DUNS_LOC                 4
#define LEN_DUTY_CODE               14
#define LEN_ENDS_IN                  4
#define LEN_ERROR_MESSAGE          255
#define LEN_ERROR_TEXT             LEN_ERROR_MESSAGE
#define LEN_EVENT                    6
#define LEN_FREIGHT_TERMS           30
#define LEN_GET_TYPE                 1
#define LEN_GROUP_NO                 4
#define LEN_HALF_NO                  5
#define LEN_IND                      1
#define LEN_INVC_ID                 10
#define LEN_INV_STATUS               2
#define LEN_ITEM                    25
#define LEN_ITEM_DESC              250  /* NLS */
#define LEN_ITEM_ID                 61
#define LEN_ITEM_NUMBER_TYPE         6
#define LEN_LAD_NO                  13
#define LEN_LAYBY                    6
#define LEN_LEAD_TIME                4
#define LEN_LIMIT_QTY               20
#define LEN_LOC                     10
#define LEN_LOC_NAME               150  /* NLS */
#define LEN_LOC_PCODE               30  /* NLS */
#define LEN_LOC_TYPE                 6
#define LEN_MARKDOWN_NBR             3
#define LEN_MASK_ID                  4
#define LEN_MERCH                    4
#define LEN_MIX_MATCH_NO            10
#define LEN_MIX_MATCH_TYPE           1
#define LEN_MONTH_454                2
#define LEN_MULTI_PROM_IND           1
#define LEN_ORDER_NO                 10
#define LEN_PACKING_METHOD           6
#define LEN_PERIOD                   2
#define LEN_PO_TYPE                  4
#define LEN_PRICE_CHANGE             8
#define LEN_PROD_TRAIT               4
#define LEN_PROMOTION               10
#define LEN_PROMO_ZONE               4
#define LEN_QTY                     12
#define LEN_QUOTA_CAT                6
#define LEN_RATE                    20
#define LEN_REASON                   2
#define LEN_REASON_KEY             255
#define LEN_RECLASS_NO               4
#define LEN_REGION                  10
#define LEN_REGION_NAME            120  /* NLS */
#define LEN_REV_NO                   6
#define LEN_ROWID                   18
#define LEN_SALES_TYPE               1
#define LEN_SHIPMENT                10
#define LEN_SHIPMENT_NO             20
#define LEN_SIZE                     6
#define LEN_SIZE_RANGE_ID            4
#define LEN_SKULIST                  8
#define LEN_STATE                    3
#define LEN_STATUS                   1
#define LEN_STORE                    LEN_LOC
#define LEN_STORE_PCODE              LEN_LOC_PCODE
#define LEN_SUBCLASS                 4
#define LEN_SUBCLASS_NAME          120  /* NLS */
#define LEN_SUPPLIER                10
#define LEN_SUPP_DIFF              120  /* NLS */
#define LEN_SUPP_PACK_SIZE          12
#define LEN_SUP_TRAIT                4
#define LEN_SYNONYM_NAME            30
#define LEN_TABLE_NAME              30
#define LEN_TABLE_OWNER             30
#define LEN_TERMS                   15
#define LEN_THREAD                  10
#define LEN_THRESHOLD_NO            10
#define LEN_THRESHOLD_TYPE           1
#define LEN_TICKET_TYPE              4
#define LEN_TIME                     6
#define LEN_TRANSFER_ZONE            4
#define LEN_TRAN_CODE                2
#define LEN_TSF_NO                  10
#define LEN_UOM                      4
#define LEN_UOM_CONV_FACTOR         20
#define LEN_USER_ID                 30
#define LEN_VALUE                   25
#define LEN_VAT_CODE_ID              6
#define LEN_VAT_REGION               4
#define LEN_VPN                     30
#define LEN_WEEK_454	             2
#define LEN_WH                       LEN_LOC
#define LEN_WH_PCODE                 LEN_LOC_PCODE
#define LEN_YEAR_454                 4
#define LEN_ZONE_GROUP_ID            4
#define LEN_ZONE_ID                 10
#define LEN_RTV_ORDER_NO            10
#define LEN_RET_AUTH                12
#define LEN_COURIER                250  /* NLS */
#define LEN_COST                    20
#define LEN_COMMENT_DESC          2000  /* NLS */
#define LEN_MRT_COMMENT           2000
#define LEN_MRT_NO                  10
#define LEN_INCLUDE_WH_INV           1
#define LEN_INVENTORY_TYPE           6
#define LEN_RTV_REASON               6
#define LEN_RTV_STATUS               6
#define LEN_ITEMLOC_LINK_ID         10
#define LEN_OLT                      5
#define LEN_SET_OF_BOOKS_ID         15
#define LEN_LAST_UPDATE_ID          15
#define LEN_PERIOD_NAME             15
#define LEN_WF_ORDER_NO             10
#define LEN_RMA_NO                  10

/*  NULL TERMINATED COLUMN LENGTHS  */

#define NULL_ADDRESS                (LEN_ADDRESS + 1)
#define NULL_ADDRESS_TYPE           (LEN_ADDRESS_TYPE + 1)
#define NULL_ADJUST_TYPE            (LEN_ADJUST_TYPE + 1)
#define NULL_ALLOC_NO               (LEN_ALLOC_NO + 1)
#define NULL_ALLOC_TYPE             (LEN_ALLOC_TYPE + 1)
#define NULL_AMT                    (LEN_AMT + 1)
#define NULL_APPLY_TO               (LEN_APPLY_TO + 1)
#define NULL_AREA                   (LEN_AREA + 1)
#define NULL_BL_AWB_ID              (LEN_BL_AWB_ID + 1)
#define NULL_BUYER                  (LEN_BUYER + 1)
#define NULL_BUY_TYPE               (LEN_BUY_TYPE + 1)
#define NULL_CARTON                 (LEN_CARTON + 1)
#define NULL_CHAIN                  (LEN_CHAIN + 1)
#define NULL_CHANGE_TYPE            (LEN_CHANGE_TYPE + 1)
#define NULL_CITY                   (LEN_CITY + 1)
#define NULL_CHANNEL_ID             (LEN_CHANNEL_ID + 1)
#define NULL_CHANNEL_TYPE           (LEN_CHANNEL_TYPE + 1)
#define NULL_CLASS                  (LEN_CLASS + 1)
#define NULL_CLASS_NAME             (LEN_CLASS_NAME + 1)
#define NULL_CLEARANCE              (LEN_CLEARANCE + 1)
#define NULL_CODE                   (LEN_CODE + 1)
#define NULL_CODE_DESC              (LEN_CODE_DESC + 1)
#define NULL_COMPANY                (LEN_COMPANY + 1)
#define NULL_COMP_NO                (LEN_COMP_NO + 1)
#define NULL_CONTRACT_NO            (LEN_CONTRACT_NO + 1)
#define NULL_COST_CHANGE            (LEN_COST_CHANGE + 1)
#define NULL_COUNTRY_ID             (LEN_COUNTRY_ID + 1)
#define NULL_CURRENCY_CODE          (LEN_CURRENCY_CODE + 1)
#define NULL_CUSTOMER               (LEN_CUSTOMER + 1)
#define NULL_CYCLE_COUNT            (LEN_CYCLE_COUNT + 1)
#define NULL_DATE                   (LEN_DATE + 1)
#define NULL_DEPT                   (LEN_DEPT + 1)
#define NULL_DEPT_NAME              (LEN_DEPT_NAME + 1)
#define NULL_DIFF_DESC              (LEN_DIFF_DESC + 1)
#define NULL_DIFF_GROUP_ID          (LEN_DIFF_GROUP_ID + 1)
#define NULL_DIFF_ID                (LEN_DIFF_ID + 1)
#define NULL_DIFF_RANGE_ID          (LEN_DIFF_RANGE_ID + 1)
#define NULL_DISCOUNT_TYPE          (LEN_DISCOUNT_TYPE + 1)
#define NULL_DISPLAY_NO             (LEN_DISPLAY_NO + 1)
#define NULL_DISTRICT               (LEN_DISTRICT + 1)
#define NULL_DISTRICT_NAME          (LEN_DISTRICT_NAME + 1)
#define NULL_DIVISION               (LEN_DIVISION + 1)
#define NULL_DIV_NAME               (LEN_DIV_NAME + 1)
#define NULL_DOMAIN                 (LEN_DOMAIN + 1)
#define NULL_DOMAIN_ID              (LEN_DOMAIN_ID + 1)
#define NULL_DUNS_NUMBER            (LEN_DUNS_NUMBER + 1)
#define NULL_DUNS_LOC               (LEN_DUNS_LOC + 1)
#define NULL_DUTY_CODE              (LEN_DUTY_CODE + 1)
#define NULL_ENDS_IN                (LEN_ENDS_IN + 1)
#define NULL_ERROR_MESSAGE          (LEN_ERROR_MESSAGE + 1)
#define NULL_ERROR_TEXT             (LEN_ERROR_TEXT + 1)
#define NULL_EVENT                  (LEN_EVENT + 1)
#define NULL_FREIGHT_TERMS          (LEN_FREIGHT_TERMS + 1)
#define NULL_GET_TYPE               (LEN_GET_TYPE + 1)
#define NULL_GROUP_NO               (LEN_GROUP_NO + 1)
#define NULL_HALF_NO                (LEN_HALF_NO + 1)
#define NULL_IND                    (LEN_IND + 1)
#define NULL_INVC_ID                (LEN_INVC_ID + 1)
#define NULL_INV_STATUS             (LEN_INV_STATUS + 1)
#define NULL_ITEM                   (LEN_ITEM + 1)
#define NULL_ITEM_DESC              (LEN_ITEM_DESC + 1)
#define NULL_ITEM_ID                (LEN_ITEM_ID + 1)
#define NULL_ITEM_NUMBER_TYPE       (LEN_ITEM_NUMBER_TYPE + 1)
#define NULL_LAD_NO                 (LEN_LAD_NO + 1)
#define NULL_LAYBY                  (LEN_LAYBY + 1)
#define NULL_LEAD_TIME              (LEN_LEAD_TIME + 1)
#define NULL_LIMIT_QTY              (LEN_LIMIT_QTY + 1)
#define NULL_LOC                    (LEN_LOC + 1)
#define NULL_LOC_NAME               (LEN_LOC_NAME + 1)
#define NULL_LOC_PCODE              (LEN_LOC_PCODE + 1)
#define NULL_LOC_TYPE               (LEN_LOC_TYPE + 1)
#define NULL_MARKDOWN_NBR           (LEN_MARKDOWN_NBR + 1)
#define NULL_MASK_ID                (LEN_MASK_ID + 1)
#define NULL_MERCH                  (LEN_MERCH + 1)
#define NULL_MIX_MATCH_NO           (LEN_MIX_MATCH_NO + 1)
#define NULL_MIX_MATCH_TYPE         (LEN_MIX_MATCH_TYPE + 1)
#define NULL_MONTH_454              (LEN_MONTH_454 + 1)
#define NULL_MULTI_PROM_IND         (LEN_MULTI_PROM_IND + 1)
#define NULL_ORDER_NO               (LEN_ORDER_NO + 1)
#define NULL_PACKING_METHOD         (LEN_PACKING_METHOD + 1)
#define NULL_PERIOD                 (LEN_PERIOD + 1)
#define NULL_PO_TYPE                (LEN_PO_TYPE + 1)
#define NULL_PRICE_CHANGE           (LEN_PRICE_CHANGE + 1)
#define NULL_PROD_TRAIT             (LEN_PROD_TRAIT + 1)
#define NULL_PROMOTION              (LEN_PROMOTION + 1)
#define NULL_PROMO_ZONE             (LEN_PROMO_ZONE + 1)
#define NULL_QTY                    (LEN_QTY + 1)
#define NULL_QUOTA_CAT              (LEN_QUOTA_CAT + 1)
#define NULL_RATE                   (LEN_RATE + 1)
#define NULL_REASON                 (LEN_REASON + 1)
#define NULL_REASON_KEY             (LEN_REASON_KEY + 1)
#define NULL_RECLASS_NO             (LEN_RECLASS_NO + 1)
#define NULL_REGION                 (LEN_REGION + 1)
#define NULL_REGION_NAME            (LEN_REGION_NAME + 1)
#define NULL_REV_NO                 (LEN_REV_NO + 1)
#define NULL_ROWID                  (LEN_ROWID + 1)
#define NULL_SALES_TYPE             (LEN_SALES_TYPE + 1)
#define NULL_SHIPMENT               (LEN_SHIPMENT + 1)
#define NULL_SHIPMENT_NO            (LEN_SHIPMENT_NO + 1)
#define NULL_SIZE                   (LEN_SIZE + 1)
#define NULL_SIZE_RANGE_ID          (LEN_SIZE_RANGE_ID + 1)
#define NULL_SKULIST                (LEN_SKULIST + 1)
#define NULL_STATE                  (LEN_STATE + 1)
#define NULL_STATUS                 (LEN_STATUS + 1)
#define NULL_STORE                  (LEN_STORE + 1)
#define NULL_STORE_PCODE            (LEN_LOC_PCODE + 1)
#define NULL_SUBCLASS               (LEN_SUBCLASS + 1)
#define NULL_SUBCLASS_NAME          (LEN_SUBCLASS_NAME + 1)
#define NULL_SUPPLIER               (LEN_SUPPLIER + 1)
#define NULL_SUPP_DIFF              (LEN_SUPP_DIFF + 1)
#define NULL_SUPP_PACK_SIZE         (LEN_SUPP_PACK_SIZE + 1)
#define NULL_SUP_TRAIT              (LEN_SUP_TRAIT + 1)
#define NULL_SYNONYM_NAME           (LEN_SYNONYM_NAME + 1)
#define NULL_TABLE_NAME             (LEN_TABLE_NAME + 1)
#define NULL_TABLE_OWNER            (LEN_TABLE_OWNER + 1)
#define NULL_TERMS                  (LEN_TERMS + 1)
#define NULL_THREAD                 (LEN_THREAD + 1)
#define NULL_THRESHOLD_NO           (LEN_THRESHOLD_NO + 1)
#define NULL_THRESHOLD_TYPE         (LEN_THRESHOLD_TYPE + 1)
#define NULL_TICKET_TYPE            (LEN_TICKET_TYPE + 1)
#define NULL_TIME                   (LEN_TIME + 1)
#define NULL_TRANSFER_ZONE          (LEN_TRANSFER_ZONE + 1)
#define NULL_TRAN_CODE              (LEN_TRAN_CODE + 1)
#define NULL_TSF_NO                 (LEN_TSF_NO + 1)
#define NULL_UOM                    (LEN_UOM + 1)
#define NULL_UOM_CONV_FACTOR        (LEN_UOM_CONV_FACTOR + 1)
#define NULL_USER_ID                (LEN_USER_ID + 1)
#define NULL_VALUE                  (LEN_VALUE + 1)
#define NULL_VAT_CODE_ID            (LEN_VAT_CODE_ID + 1)
#define NULL_VAT_REGION             (LEN_VAT_REGION + 1)
#define NULL_VPN                    (LEN_VPN + 1)
#define NULL_WEEK_454               (LEN_WEEK_454 + 1)
#define NULL_WH                     (LEN_WH + 1)
#define NULL_WH_PCODE               (LEN_LOC_PCODE + 1)
#define NULL_YEAR_454               (LEN_YEAR_454 + 1)
#define NULL_ZONE_GROUP_ID          (LEN_ZONE_GROUP_ID + 1)
#define NULL_ZONE_ID                (LEN_ZONE_ID + 1)
#define NULL_RTV_ORDER_NO           (LEN_RTV_ORDER_NO + 1)
#define NULL_RET_AUTH               (LEN_RET_AUTH + 1)
#define NULL_COURIER                (LEN_COURIER + 1)
#define NULL_COST                   (LEN_COST + 1)
#define NULL_COMMENT_DESC           (LEN_COMMENT_DESC + 1)
#define NULL_MRT_COMMENT            (LEN_MRT_COMMENT + 1)
#define NULL_MRT_NO                 (LEN_MRT_NO + 1)
#define NULL_INCLUDE_WH_INV         (LEN_INCLUDE_WH_INV + 1)
#define NULL_INVENTORY_TYPE         (LEN_INVENTORY_TYPE + 1)
#define NULL_RTV_REASON             (LEN_RTV_REASON + 1)
#define NULL_RTV_STATUS             (LEN_RTV_REASON + 1)
#define NULL_ITEMLOC_LINK_ID        (LEN_ITEMLOC_LINK_ID + 1)
#define NULL_OLT                    (LEN_OLT + 1)
#define NULL_SET_OF_BOOKS_ID        (LEN_SET_OF_BOOKS_ID + 1)
#define NULL_LAST_UPDATE_ID         (LEN_LAST_UPDATE_ID + 1)
#define NULL_PERIOD_NAME            (LEN_PERIOD_NAME + 1)
#define NULL_WF_ORDER_NO            (LEN_WF_ORDER_NO + 1)
#define NULL_RMA_NO                 (LEN_RMA_NO + 1)
