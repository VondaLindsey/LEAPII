CREATE OR REPLACE PACKAGE BODY SMR_PACK_SQL AS
  --------------------------------------------------------------------------------------------------------------------------------------------------
  --Program Name : SMR_PACK_SQL
  --Description  : This package is used for custom pack code. It is called from the smrpackitem and smrbuypkcopy forms
  --
  -- Modification History
  -- Version Date      Developer   Issue    Description
  -- ======= ========= =========== ======== ==========================================================================================
  -- 1.00    06-SEP-13 P.Dinsdale  CR00305  Original
  -- 1.01    01-Jun-15 Murali      Leap     The package SMR_PACK_SQL was modified to allow copy of 
  --                                        Vendor packs from Existing Vendor packs. This package is 
  --                                        invoked from an existing Custom form to create new complex 
  --                                        packs from existing complex packs. The existing restriction to 
  --                                        allow only copy of byer packs will need to be modified to also 
  --                                        include the Vendor Packs.
  --------------------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------
--PRIVATE FUNCTIONS
--------------------------------------------------------------------------------------------------
FUNCTION IS_PACK (O_error_message       OUT rtk_errors.rtk_text%TYPE,
                  I_item             IN     item_master.item%TYPE,
                  IO_is_pack         IN OUT BOOLEAN)
  return BOOLEAN IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.IS_PACK';

  CURSOR c_pack_type IS
  SELECT pack_type
    FROM item_master
   WHERE item = I_item;

  L_pack_type VARCHAR2(1);

BEGIN

   IF I_item IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_ITEM',
                                            'NULL',
                                            'NOT NULL');
      RETURN FALSE;
   END IF;

   OPEN  c_pack_type;
   FETCH c_pack_type INTO L_pack_type;
   CLOSE c_pack_type;

   IF L_pack_type IS NULL THEN
      IO_is_pack := FALSE;
   ELSE
      IO_is_pack := TRUE;
   END IF;

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

--------------------------------------------------------------------------------------------------
--PUBLIC FUNCTIONS
--------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------
--- FUNCTION: ITEMS_IN_PACK
--- PURPOSE:  Returns the number of distinct items in a pack, and the sum of pack_qty
--------------------------------------------------------------------------------------------------
FUNCTION ITEMS_IN_PACK(O_error_message       OUT rtk_errors.rtk_text%TYPE,
                       I_item             IN     item_master.item%TYPE,
                       IO_distinct_items  IN OUT NUMBER,
                       IO_count_items     IN OUT NUMBER)
  return BOOLEAN IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.ITEMS_IN_PACK';

  L_is_pack BOOLEAN;

  CURSOR C_pack_details IS
  SELECT COUNT(DISTINCT pb.item), NVL(SUM(pb.pack_item_qty),0)
    FROM packitem_breakout pb,
         v_smr_packitem_itemdesc v_spi  --JOIN WITH THIS VIEW SO THAT FORM CAN SHOW PACK QUANTITY IN REAL TIME
   WHERE pb.pack_no = I_item
     AND pb.item = v_spi.item
     AND NVL(v_spi.pack_qty ,0) > 0;

BEGIN

   if I_item IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_ITEM',
                                            'NULL',
                                            'NOT NULL');
      RETURN FALSE;
   END IF;

   IF IS_PACK (O_error_message,
               I_item,
               L_is_pack) = FALSE THEN
      RETURN FALSE;
   ELSE

      IF L_is_pack = FALSE then
         O_error_message := 'Item '||I_item||' is not a pack.';
         RETURN FALSE;
      END IF;

   END IF;

   OPEN  C_pack_details;
   FETCH C_pack_details INTO IO_distinct_items, IO_count_items;
   CLOSE C_pack_details;

   IO_distinct_items := NVL(IO_distinct_items,0);
   IO_count_items    := NVL(IO_count_items,0);

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

--------------------------------------------------------------------------------------------------
--- FUNCTION: UPDATE_PACKITEM
--- PURPOSE:  Updates the pack_qty of a single record in packitem
--------------------------------------------------------------------------------------------------
FUNCTION UPDATE_PACKITEM (O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                          I_pack_no       IN     packitem.pack_no%TYPE,
                          I_seq_no        IN     packitem.seq_no%TYPE,
                          I_qty           IN     packitem.pack_qty%TYPE)
   RETURN BOOLEAN is
   ---
   L_program varchar2(64) := L_PACKAGE_NAME||'.UPDATE_PACKITEM';

   L_table              VARCHAR2(30)    := 'PACKITEM';
   RECORD_LOCKED        EXCEPTION;
   PRAGMA               EXCEPTION_INIT(Record_Locked, -54);
   ---
   CURSOR C_LOCK_RECORDS is
   SELECT 'x'
     FROM PACKITEM
    WHERE pack_no = I_pack_no
      AND seq_no = I_seq_no
      FOR UPDATE NOWAIT;

BEGIN

   IF I_pack_no IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_PACK_NO',
                                            'NULL',
                                            'NOT NULL');
      RETURN FALSE;
   END IF;
   IF I_seq_no IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_SEQ_NO',
                                            'NULL',
                                            'NOT NULL');
      RETURN FALSE;
   END IF;
   IF NVL(I_qty, 0) <= 0 then
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_QTY',
                                            nvl(to_char(I_qty), 'NULL'),
                                            '> 0');
      RETURN FALSE;
   END IF;
   ---
   SQL_LIB.SET_MARK('OPEN',
                    'C_LOCK_RECORDS',
                    'PACKITEM',
                    'PACK_NO: '||I_pack_no);
   OPEN C_LOCK_RECORDS;
   SQL_LIB.SET_MARK('CLOSE',
                    'C_LOCK_RECORDS',
                    'PACKITEM',
                    'PACK_NO: '||I_pack_no);
   close C_LOCK_RECORDS;
   ---
   SQL_LIB.SET_MARK('UPDATE',
                    'PACKITEM',
                    'PACK_NO: '||I_pack_no||', seq_no: '||I_seq_no,
                    NULL);

   UPDATE packitem
      SET pack_qty = I_qty,
          last_update_datetime = SYSDATE,
          last_update_id = USER
    WHERE pack_no  = I_pack_no
      AND seq_no   = I_seq_no;

   ---
   RETURN TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                            L_table,
                                            I_pack_no,
                                            NULL);
      RETURN FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;
END UPDATE_PACKITEM;

--------------------------------------------------------------------------------------------------
--- FUNCTION: UPDATE_SMR_PACKITEM
--- PURPOSE:  Updates the pack_qty of a single record in smr_packitem
--------------------------------------------------------------------------------------------------
FUNCTION UPDATE_SMR_PACKITEM (O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                              I_pack_no       IN     packitem.pack_no%TYPE,
                              I_seq_no        IN     packitem.seq_no%TYPE,
                              I_qty           IN     packitem.pack_qty%TYPE)
   return BOOLEAN is
   ---
   L_program varchar2(64) := L_PACKAGE_NAME||'.UPDATE_SMR_PACKITEM';

   L_table              VARCHAR2(30)    := 'SMR_PACKITEM';
   RECORD_LOCKED        EXCEPTION;
   PRAGMA               EXCEPTION_INIT(Record_Locked, -54);
   ---
   CURSOR C_LOCK_RECORDS is
   SELECT 'x'
     FROM smr_packitem
    WHERE pack_no = I_pack_no
      AND seq_no = I_seq_no
      FOR UPDATE NOWAIT;

BEGIN

   IF I_pack_no IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_PACK_NO',
                                            'NULL',
                                            'NOT NULL');
      RETURN FALSE;
   END IF;
   IF I_seq_no IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_SEQ_NO',
                                            'NULL',
                                            'NOT NULL');
      RETURN FALSE;
   END IF;

   IF NVL(I_qty, 0) < 0 then
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_PARM',
                                            'I_QTY',
                                            nvl(to_char(I_qty), 'NULL'),
                                            '>= 0');
      RETURN FALSE;
   END IF;
   ---
   SQL_LIB.SET_MARK('OPEN',
                    'C_LOCK_RECORDS',
                    'PACKITEM',
                    'PACK_NO: '||I_pack_no);
   OPEN C_LOCK_RECORDS;
   SQL_LIB.SET_MARK('CLOSE',
                    'C_LOCK_RECORDS',
                    'PACKITEM',
                    'PACK_NO: '||I_pack_no);
   CLOSE C_LOCK_RECORDS;
   ---
   SQL_LIB.SET_MARK('UPDATE',
                    'PACKITEM',
                    'PACK_NO: '||I_pack_no||', seq_no: '||I_seq_no,
                    NULL);

   UPDATE smr_packitem
      SET pack_qty = I_qty,
          last_update_datetime = SYSDATE,
          last_update_id = USER
    WHERE pack_no  = I_pack_no
      AND seq_no   = I_seq_no;

   ---
   RETURN TRUE;
EXCEPTION
   WHEN RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                            L_table,
                                            I_pack_no,
                                            NULL);
      RETURN FALSE;
   WHEN OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;
END UPDATE_SMR_PACKITEM;

--------------------------------------------------------------------------------------------------
--- FUNCTION: CLEAN_GTT
--- PURPOSE:  Empties the global temporary
--------------------------------------------------------------------------------------------------
FUNCTION CLEAN_GTT (O_error_message IN OUT rtk_errors.rtk_text%TYPE)
  RETURN BOOLEAN
 IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.CLEAN_GTT';

BEGIN

  --Clean out the global table
  DELETE FROM smr_packitem;

  RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;
END CLEAN_GTT;
--------------------------------------------------------------------------------------------------
--- FUNCTION: POPULATE_GTT
--- PURPOSE:  Populates the global temporary table with the packitem details of the pack_no
--            passed in.
--------------------------------------------------------------------------------------------------
FUNCTION POPULATE_GTT (O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                       I_pack_no       IN     packitem.pack_no%TYPE)
  return BOOLEAN IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.POPULATE_GTT';
  L_is_pack BOOLEAN;

BEGIN

  IF I_pack_no IS NULL THEN
     O_error_message := 'Parameter I_pack_no cannot be passed as null to function '||L_program;
     RETURN FALSE;
  END IF;

  IF IS_PACK (O_error_message,
              I_pack_no,
              L_is_pack) = FALSE THEN
     RETURN FALSE;
  END IF;

  IF L_is_pack = FALSE THEN
     O_error_message := 'Item '||I_pack_no||' is not a pack.';
     RETURN FALSE;
  END IF;

  --Clean out the global table
  DELETE FROM smr_packitem
   WHERE pack_no = I_pack_no;

  --Repopulate the global table
  INSERT INTO smr_packitem
  SELECT *
    FROM packitem
   WHERE pack_no = I_pack_no;

  RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;
END POPULATE_GTT;

--------------------------------------------------------------------------------------------------
--- FUNCTION: POPULATE_GTT
--- PURPOSE:  Populates the global temporary table with the packitem details
--            of the I_like_pack_no passed in, but using I_pack_no as the new pack_no
--------------------------------------------------------------------------------------------------
FUNCTION POPULATE_GTT (O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                       I_pack_no       IN     packitem.pack_no%TYPE,
                       I_like_pack_no  IN     packitem.pack_no%TYPE)
  return BOOLEAN IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.POPULATE_GTT';
  L_is_pack BOOLEAN;

BEGIN

  IF I_pack_no IS NULL THEN
     O_error_message := 'Parameter I_pack_no cannot be passed as null to function '||L_program;
     RETURN FALSE;
  END IF;

  IF IS_PACK (O_error_message,
              I_pack_no,
              L_is_pack) = FALSE THEN
     RETURN FALSE;
  END IF;

  IF L_is_pack = FALSE THEN
     O_error_message := 'Item '||I_pack_no||' is not a pack.';
     RETURN FALSE;
  END IF;

  --Clean out the global table
  DELETE FROM smr_packitem
   WHERE pack_no = I_pack_no;

  --Repopulate the global table
  INSERT INTO smr_packitem
  SELECT I_pack_no
        ,SEQ_NO
        ,ITEM
        ,ITEM_PARENT
        ,PACK_TMPL_ID
        ,PACK_QTY
        ,CREATE_DATETIME
        ,LAST_UPDATE_DATETIME
        ,LAST_UPDATE_ID
    FROM packitem
   WHERE pack_no = I_like_pack_no;

  RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;
END POPULATE_GTT;


--------------------------------------------------------------------------------------------------
--- FUNCTION: PACKITEM_EXISTS
--- PURPOSE:  Sets O_exists to true if a packitem record exists for the pack
--------------------------------------------------------------------------------------------------
FUNCTION PACKITEM_EXISTS (O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                          O_exists        IN OUT BOOLEAN,
                          I_pack_no       IN     packitem.pack_no%TYPE,
                          I_seq_no        IN     packitem.seq_no%TYPE)
  return BOOLEAN IS
  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.PACKITEM_EXISTS';


  CURSOR c_packitem_exists is
  SELECT 'x'
    FROM packitem
   WHERE pack_no = I_pack_no
     AND seq_no = I_seq_no;

  L_exists varchar2(1);


BEGIN

  O_exists := TRUE;

  OPEN  c_packitem_exists;
  FETCH c_packitem_exists INTO L_exists;
  CLOSE c_packitem_exists;

  if L_exists IS NULL THEN
    O_exists := FALSE;
  END IF;

  return true;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

--------------------------------------------------------------------------------------------------
--- FUNCTION: SMR_PACKITEM_EXISTS
--- PURPOSE:  Sets O_exists to true if a smr_packitem record exists for the pack
--------------------------------------------------------------------------------------------------
FUNCTION SMR_PACKITEM_EXISTS (O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                              O_exists        IN OUT BOOLEAN,
                              I_pack_no       IN     packitem.pack_no%TYPE,
                              I_item          IN     PACKITEM.ITEM%TYPE)
  return BOOLEAN IS
  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.SMR_PACKITEM_EXISTS';


  CURSOR c_packitem_exists is
  SELECT 'x'
    FROM smr_packitem
   WHERE pack_no = I_pack_no
     AND item = I_item;

  L_exists varchar2(1);


BEGIN

  O_exists := TRUE;

  OPEN  c_packitem_exists;
  FETCH c_packitem_exists into L_exists;
  CLOSE c_packitem_exists;

  if L_exists IS NULL THEN
    O_exists := FALSE;
  END IF;

  return true;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

--------------------------------------------------------------------------------------------------
--- FUNCTION: DELETE_EMPTY_RECORDS
--- PURPOSE:  Removes packitem and packitem_breakout records where corresponding
---           v_smr_packitem_itemdesc record has null or 0 pack_qty
--------------------------------------------------------------------------------------------------
FUNCTION DELETE_EMPTY_RECORDS (O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                               I_pack_no       IN     packitem.pack_no%TYPE)
  return BOOLEAN IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.DELETE_EMPTY_RECORDS';
  L_pack_ind         item_master.pack_ind%TYPE;
  L_sellable_ind     ITEM_MASTER.SELLABLE_IND%TYPE;
  L_orderable_ind    ITEM_MASTER.ORDERABLE_IND%TYPE;
  L_pack_type        ITEM_MASTER.PACK_TYPE%TYPE;

  CURSOR c_no_pack_qty IS
  SELECT item,
         item_parent
    FROM packitem pi
   WHERE pack_no = I_pack_no
     AND NOT EXISTS (SELECT 'x'
                       FROM v_smr_packitem_itemdesc
                      WHERE pack_no = I_pack_no
                        AND seq_no =  pi.seq_no);

BEGIN

    DELETE FROM v_smr_packitem_itemdesc WHERE pack_no = I_pack_no and NVL(pack_qty,0) = 0;

    FOR rec in c_no_pack_qty LOOP

       IF ITEM_ATTRIB_SQL.GET_PACK_INDS(O_error_message,
                                        L_pack_ind,
                                        L_sellable_ind,
                                        L_orderable_ind,
                                        L_pack_type,
                                        rec.item) = FALSE THEN
          RETURN FALSE;
       END IF;

       IF PACKITEM_ADD_SQL.DELETE_PACKITEM_BREAKOUT(O_error_message,
                                                    I_pack_no,
                                                    rec.item,
                                                    rec.item_parent,
                                                    L_pack_ind) = FALSE THEN
          RETURN FALSE;
       END IF;

    END LOOP;

    DELETE FROM packitem pi
     WHERE pack_no = I_pack_no
       AND NOT EXISTS (SELECT 'x'
                         FROM v_smr_packitem_itemdesc
                        WHERE pack_no = I_pack_no
                          AND seq_no = pi.seq_no);

    RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

--------------------------------------------------------------------------------------------------
--- FUNCTION: DELETE_PACK_ITEM
--- PURPOSE:  Removes pack records for an item.
--------------------------------------------------------------------------------------------------
FUNCTION DELETE_PACK_ITEM(O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                          I_pack_no       IN     packitem.pack_no%TYPE,
                          I_seq_no        IN     packitem.seq_no%TYPE,
                          I_item          IN     packitem.item%TYPE,
                          I_item_parent   IN     packitem.item_parent%TYPE,
                          I_pack_ind      IN     item_master.pack_ind%TYPE)
  return BOOLEAN IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.DELETE_PACK_ITEM';

BEGIN

   DELETE FROM v_smr_packitem_itemdesc WHERE pack_no = I_pack_no AND seq_no = I_seq_no;

   IF PACKITEM_ADD_SQL.DELETE_PACKITEM_BREAKOUT(O_error_message,
                                                I_pack_no,
                                                I_item,
                                                I_item_parent,
                                                I_pack_ind) = FALSE then
      RETURN FALSE;
   END IF;

   DELETE FROM packitem WHERE pack_no = I_pack_no and seq_no = I_seq_no;

   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

--------------------------------------------------------------------------------------------------
--- FUNCTION: COMPARE_QTY_TO_UOM
--- PURPOSE:  Sets I_valid to false if the I_qty value does not match the item UOM.
--------------------------------------------------------------------------------------------------
FUNCTION COMPARE_QTY_TO_UOM(O_error_message  IN OUT rtk_errors.rtk_text%TYPE,
                            I_valid          IN OUT BOOLEAN,
                            I_item           IN OUT packitem.item%TYPE,
                            I_qty            IN OUT packitem.pack_qty%TYPE)

  return BOOLEAN IS

  L_program VARCHAR2(64) := L_PACKAGE_NAME||'.COMPARE_QTY_TO_UOM';

  L_unit_of_measure ITEM_MASTER.standard_uom%type;
  L_standard_class  UOM_CLASS.UOM_CLASS%TYPE;
  L_conv_factor     ITEM_MASTER.UOM_CONV_FACTOR%TYPE;
  L_get_class_ind   varchar2(255) := 'Y';

BEGIN

   I_valid := true;

   IF ITEM_ATTRIB_SQL.GET_STANDARD_UOM(O_error_message,
                                       L_unit_of_measure,
                                       L_standard_class,
                                       L_conv_factor,
                                       I_item,
                                       L_get_class_ind) = FALSE then

     RETURN FALSE;

   END IF;

   IF L_unit_of_measure = 'EA' AND NVL(I_qty,0) != round(NVL(I_qty,0)) THEN
      O_error_message := 'Quantity should be a whole number as item standard UOM is eaches.';
      I_valid := false;
   END IF;

   return true;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

--------------------------------------------------------------------------------------------------
--- FUNCTION: IS_VALID_TO_COPY
--- PURPOSE:  Sets I_valid to false if the item is not valid for the smrbuypkcopy form
--------------------------------------------------------------------------------------------------
FUNCTION IS_VALID_TO_COPY(O_error_message  IN OUT rtk_errors.rtk_text%TYPE,
                          I_valid          IN OUT BOOLEAN,
                          I_item           IN OUT packitem.item%TYPE)

  return BOOLEAN IS

  L_program     VARCHAR2(64) := L_PACKAGE_NAME||'.IS_VALID_TO_COPY';
  L_item_record ITEM_MASTER%ROWTYPE;

  CURSOR c_allow_sell_buy_pk is
  SELECT allow_sell_buy_pk
    FROM smr_system_options;

  L_allow_sell_buy_pk  varchar2(1);

BEGIN

   I_valid := FALSE;

   --get item details
   OPEN  c_allow_sell_buy_pk;
   FETCH c_allow_sell_buy_pk INTO L_allow_sell_buy_pk;
   CLOSE c_allow_sell_buy_pk;

   IF ITEM_ATTRIB_SQL.GET_ITEM_MASTER (O_error_message,
                                       L_item_record,
                                       I_item) = FALSE THEN
      RETURN FALSE;
   END IF;

   --Set valid false if not a buyer pack of type ITEM
   IF nvl(L_item_record.pack_type,'x') not in ('B' ,'V')  -- V 1.01
      OR L_item_record.pack_ind != 'Y'
      OR L_item_record.item_number_type != 'ITEM'
      THEN
         I_valid := FALSE;
         RETURN TRUE;
   END IF;

   --handle custom system option
   IF L_allow_sell_buy_pk = 'N' AND L_item_record.sellable_ind = 'N' THEN
      I_valid := TRUE;
   ELSIF L_allow_sell_buy_pk = 'Y' THEN
      I_valid := TRUE;
   END IF;

   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      RETURN FALSE;

END;

-------------------------------------------------------------------------------
--    Name: GET_SMR_SYSTEM_OPTIONS
-- Purpose: This function returns all smr_system_options in one rowtype variable.
-------------------------------------------------------------------------------
FUNCTION GET_SMR_SYSTEM_OPTIONS(O_error_message          IN OUT rtk_errors.rtk_text%TYPE,
                                O_smr_system_options_row    OUT  SMR_SYSTEM_OPTIONS%ROWTYPE)
RETURN BOOLEAN IS

   L_program   VARCHAR2(64) := L_PACKAGE_NAME ||'.GET_SMR_SYSTEM_OPTIONS';

   CURSOR C_SMR_SYSTEM_OPTIONS is
   SELECT *
     FROM smr_system_options;

BEGIN

   OPEN  C_SMR_SYSTEM_OPTIONS;
   FETCH C_SMR_SYSTEM_OPTIONS into O_smr_system_options_row;
   CLOSE C_SMR_SYSTEM_OPTIONS;

   return TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            to_char(SQLCODE));
      return FALSE;
END GET_SMR_SYSTEM_OPTIONS;

-------------------------------------------------------------------------------
--    Name: UPDATE_ITEM_DESC
-- Purpose: Updates the item_desc of the passed in item
-------------------------------------------------------------------------------
FUNCTION UPDATE_ITEM_DESC(O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                          I_item          IN     item_master.item%TYPE,
                          I_item_desc     IN     item_master.item_desc%TYPE)
   RETURN BOOLEAN IS

   L_program      VARCHAR2(50) := L_PACKAGE_NAME || '.UPDATE_ITEM_DESC';

BEGIN
   if not ITEM_MASTER_SQL.LOCK_ITEM_MASTER(O_error_message,
                                           I_item) then
      return FALSE;
   end if;

   UPDATE item_master
      SET  item_desc = I_item_desc
    WHERE item = I_item;

   ---
   return TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            to_char(SQLCODE));
      return FALSE;

END UPDATE_ITEM_DESC;

-------------------------------------------------------------------------------
--    Name: COPY_PACK_DETAILS
-- Purpose: creates packitem and packitem_breakout records like an existing item
-------------------------------------------------------------------------------
FUNCTION COPY_PACK_DETAILS(O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                           I_pack_no       IN     item_master.item%TYPE,
                           I_like_pack_no  IN     item_master.item%TYPE)
  return BOOLEAN is

   L_program      VARCHAR2(50) := L_PACKAGE_NAME || '.COPY_PACK_DETAILS';

   CURSOR c_items is
   SELECT pi.item,
          null pack_tmpl,
          pi.pack_qty,
          im.pack_ind
     FROM packitem pi,
          item_master im
    WHERE pi.item = im.item
      AND pi.pack_no = I_pack_no;

BEGIN

     INSERT INTO packitem
     SELECT I_pack_no
           ,seq_no
           ,item
           ,item_parent
           ,pack_tmpl_id
           ,pack_qty
           ,sysdate
           ,sysdate
           ,user
       FROM packitem
      WHERE pack_no = I_like_pack_no;


   for rec in c_items loop
      if PACKITEM_ADD_SQL.INSERT_PACKITEM_BREAKOUT(O_error_message,
                                                   I_pack_no,
                                                   rec.item,
                                                   rec.pack_tmpl,
                                                   rec.pack_ind,
                                                   rec.pack_qty) = FALSE then
         return false;
      end if;
   end loop;
   ---

   return true;


EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            to_char(SQLCODE));
      return FALSE;

END COPY_PACK_DETAILS;

-------------------------------------------------------------------------------
--    Name: RECORDS_WITH_QTY
-- Purpose: Returns the count of smr_packitem records for the passed in pack_no
--          with at least 1 unit qty
-------------------------------------------------------------------------------
FUNCTION RECORDS_WITH_QTY(O_error_message IN OUT rtk_errors.rtk_text%TYPE,
                          I_pack_no       IN     item_master.item%TYPE,
                          I_count         IN OUT NUMBER)
  return BOOLEAN is

   L_program      VARCHAR2(50) := L_PACKAGE_NAME || '.RECORDS_WITH_QTY';

   CURSOR c_items is
   SELECT count(*)
     FROM smr_packitem
    WHERE pack_no = I_pack_no
      AND pack_qty > 0;

BEGIN

   OPEN  c_items;
   FETCH c_items into I_count;
   CLOSE c_items;

   return true;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            to_char(SQLCODE));
      return FALSE;

END RECORDS_WITH_QTY;

END SMR_PACK_SQL;
/