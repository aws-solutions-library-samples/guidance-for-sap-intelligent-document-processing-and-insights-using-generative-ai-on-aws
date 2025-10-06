class ZCL_ZINVOICE_APP_DPC_EXT definition
  public
  inheriting from ZCL_ZINVOICE_APP_DPC
  create public .

public section.

  methods /IWBEP/IF_MGW_APPL_SRV_RUNTIME~CREATE_STREAM
    redefinition .
  methods /IWBEP/IF_MGW_APPL_SRV_RUNTIME~EXECUTE_ACTION
    redefinition .
  methods /IWBEP/IF_MGW_APPL_SRV_RUNTIME~GET_EXPANDED_ENTITY
    redefinition .
  methods /IWBEP/IF_MGW_APPL_SRV_RUNTIME~GET_STREAM
    redefinition .
protected section.

  methods INVOICES_GET_ENTITY
    redefinition .
  methods INVOICES_GET_ENTITYSET
    redefinition .
  methods ITEMS_GET_ENTITYSET
    redefinition .
private section.

  data AT_EXPENSE_SUMMARY type ZCL_AWS_TEXTRACT_HELPER=>TT_EXPENSE_SUMMARY .
  data GV_PROFILE type /AWS1/RT_PROFILE_ID .
  data GV_BUKRS type BUKRS value '1710' ##NO_TEXT.
  data GV_YEAR type GJAHR value 2024 ##NO_TEXT.

  methods GET_OVERALL_SUMMARY_SCORE
    returning
      value(RE_SCORE) type /AWS1/TEXPERCENT .
  methods GET_VALUE_EXPENSETYPE
    importing
      !IE_TYPE type STRING
    returning
      value(RE_VALUE) type STRING .
  methods REMOVE_DUPLICATES_BY_SCORE .
  methods ANALYZE_INVOICE_TEXTRACT
    importing
      !IM_BUCKET type STRING
      !IM_KEY type STRING
    exceptions
      DUPLICATE_INVOICE
      TEXTRACT_ERROR .
  methods GET_CURRENCY_FOR_EXPENSETYPE
    importing
      !IE_TYPE type STRING
    returning
      value(RE_VALUE) type STRING .
  methods CONVERT_ITEMS
    importing
      !IE_KEY type STRING
      !IE_ITEMS type ZCL_AWS_TEXTRACT_HELPER=>TT_EXPENSE_ITEM
    exporting
      value(RE_ITEMS) type ZCL_ZINVOICE_APP_MPC=>TT_ITEM .
  methods GET_PROFILE_USER .
  methods CREATE_AUDIT_INDX
    importing
      !IT_EXPENSE type ZCL_AWS_TEXTRACT_HELPER=>TT_EXPENSES .
  methods POST_INVOICE
    importing
      !IE_EXPENSE type ZCL_AWS_TEXTRACT_HELPER=>TY_EXPENSE
    exporting
      !ET_RETURN type BAPIRET2_T
      !EE_KEY type BELNR_D .
  methods SNS_SUBSCRIPTION
    importing
      !IE_MAIL type STRING .
  methods SEND_NOTIFICATION
    importing
      !IE_KEY type BELNR_D .
  methods TRANSLATE_DESCRIPTION
    importing
      !IE_KEY type BELNR_D
      !IE_DESCRIPTION type STRING
      !IE_ITEM type NUMC3 .
  methods SAVE_ITEM_TEXT
    importing
      !IE_KEY type BELNR_D
      !IE_DESCRIPTION type STRING
      !IE_ITEM type NUMC3
      !IE_LANGU type STRING .
  methods WRITE_DATA_TO_S3
    importing
      !IE_KEY type STRING .
ENDCLASS.



CLASS ZCL_ZINVOICE_APP_DPC_EXT IMPLEMENTATION.


  METHOD /iwbep/if_mgw_appl_srv_runtime~create_stream.

    DATA lo_s3_helper TYPE REF TO zcl_aws_s3_helper.
    DATA lv_slug TYPE string.
    DATA ls_invoicedocument type zcl_zinvoice_app_mpc=>ts_invoicedocument.

    get_profile_user( ).

    DATA(lo_container) = mo_context->get_message_container( ).

*** switch case ***
    CASE iv_entity_set_name.

      WHEN 'InvoiceDocuments'.
        TRY.
            lo_s3_helper = NEW zcl_aws_s3_helper( im_profile = gv_profile ).

          CATCH /aws1/cx_rt_technical_generic INTO DATA(lo_cx_technical_generic).
            lo_container->add_message_text_only(
              EXPORTING
                iv_msg_type               = lo_container->gcs_message_type-error
                iv_msg_text               = CONV bapi_msg( lo_cx_technical_generic->get_text( ) )   " Message Text
                iv_entity_type            = iv_entity_name ).

            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                message_container = lo_container.

          CATCH /aws1/cx_rt_no_auth_generic INTO DATA(lo_cx_auth_generic).

            lo_container->add_message_text_only(
               EXPORTING
                 iv_msg_type               = lo_container->gcs_message_type-error
                 iv_msg_text               = CONV bapi_msg( |{ lo_cx_auth_generic->av_profile_id }| &&
                                             | { lo_cx_technical_generic->get_text( ) }| )
                 iv_entity_type            = iv_entity_name ).

            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                message_container = lo_container.

          CATCH /aws1/cx_rt_service_generic INTO DATA(lo_cx_service_generic).

            lo_container->add_message_text_only(
              EXPORTING
                iv_msg_type               = lo_container->gcs_message_type-error
                iv_msg_text               = CONV bapi_msg( lo_cx_service_generic->get_text( ) )   " Message Text
                iv_entity_type            = iv_entity_name ).

            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                message_container = lo_container.

        ENDTRY.

** upload the data
        DATA(lv_uuid) = cl_system_uuid=>create_uuid_x16_static( ).

** Try Creating a buckert if not exists
        TRY.
            lo_s3_helper->create_bucket(
                 im_bucket = |invoice-images-sapinsider-{ to_lower( sy-uname ) }|
                 ).
          CATCH /aws1/cx_s3_bucketalrdyexists.
          catch /aws1/cx_s3_bktalrdyownedbyyou.
        ENDTRY.

        SPLIT iv_slug AT '.' INTO TABLE DATA(lt_slug).

        READ TABLE lt_slug INTO DATA(ls_slug) INDEX lines( lt_slug ).
        IF sy-subrc = 0.
           lv_slug = |{ lv_uuid }.{ ls_slug }|.
        ENDIF.

        lo_s3_helper->put_object( im_bucket = |invoice-images-sapinsider-{ to_lower( sy-uname ) }|
                                  im_key    = |{ lv_slug }|
                                  im_data   = is_media_resource-value ).



** call textract to analyze the contents and store the invoice information
        analyze_invoice_textract(
          EXPORTING
            im_bucket                    =  |invoice-images-sapinsider-{ to_lower( sy-uname ) }|
            im_key                       =  |{ lv_slug }|
          EXCEPTIONS
            duplicate_invoice = 1
            textract_error = 2 ).

        CASE sy-subrc.

          WHEN 0.

           ls_invoicedocument-xblnr = '1'.
           ls_invoicedocument-filename = lv_slug.
           ls_invoicedocument-filetype = is_media_resource-mime_type.

           copy_data_to_ref(
             EXPORTING
               is_data = ls_invoicedocument
             CHANGING
               cr_data = er_entity
           ).

          WHEN 1.

            lo_container->add_message_text_only(
                EXPORTING
                  iv_msg_type               = lo_container->gcs_message_type-error
                  iv_msg_text               = |Error ocurred - Duplicate Invoice found|   " Message Text
                  iv_entity_type            = iv_entity_name ).

            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                message_container = lo_container.

          WHEN 2.

              lo_s3_helper->delete_object( im_bucket = |invoices-{ to_lower( sy-uname ) }|
                                  im_key    = |{ lv_slug }| ).

            lo_container->add_message_text_only(
                EXPORTING
                  iv_msg_type               = lo_container->gcs_message_type-error
                  iv_msg_text               = |Error occured during document analysis - unsupported document/missing key values|   " Message Text
                  iv_entity_type            = iv_entity_name ).

            RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
              EXPORTING
                message_container = lo_container.


          WHEN OTHERS.

        ENDCASE.

      WHEN OTHERS.

    ENDCASE.

  ENDMETHOD.


  METHOD /iwbep/if_mgw_appl_srv_runtime~execute_action.

    DATA lt_expenses        TYPE zcl_aws_textract_helper=>tt_expenses.
    DATA lv_index_id        TYPE char22.
    DATA lv_msg             TYPE string.
    DATA lt_return          TYPE TABLE OF bapiret2.

    DATA ls_return          TYPE zcl_zinvoice_app_mpc=>postreturn.
    DATA(ls_indx) = VALUE indx( aedat = sy-datum
                                  usera = sy-uname ).

    DATA(lo_container) = mo_context->get_message_container( ).

    lv_index_id        = |AP-{ sy-uname }|.

    CASE iv_action_name.

      WHEN 'PostDocument'.

        DATA(lv_invoice_key) =  it_parameter[ name = 'InvoiceNumber' ]-value.

        IMPORT expenses = lt_expenses FROM DATABASE indx(zp) ID lv_index_id
               ACCEPTING PADDING.

        LOOP AT lt_expenses ASSIGNING FIELD-SYMBOL(<fs_expense>).

          at_expense_summary = <fs_expense>-expense_summary.

          remove_duplicates_by_score( ).

          TRY.
              IF  at_expense_summary[
                          expense_type = 'INVOICE_RECEIPT_ID' ]-value EQ
                       lv_invoice_key.

                post_invoice( EXPORTING ie_expense = <fs_expense>
                              IMPORTING et_return = lt_return
                                        ee_key = <fs_expense>-belnr ).


                ls_return-belnr = <fs_expense>-belnr.

                IF <fs_expense>-belnr IS NOT INITIAL.
                  <fs_expense>-status = 'Posted'.


                ENDIF.
              ENDIF.
            CATCH cx_sy_itab_line_not_found.
              CONTINUE.
          ENDTRY.
        ENDLOOP.

        IF ls_return-belnr IS NOT INITIAL.

* export
          EXPORT expenses = lt_expenses TO DATABASE indx(zp) ID lv_index_id
                FROM ls_indx COMPRESSION ON.

* store all the invoices for auditing
          create_audit_indx( lt_expenses ).
* export to s3
          write_data_to_s3( lv_invoice_key ).

          me->copy_data_to_ref(
           EXPORTING
           is_data = ls_return
           CHANGING
           cr_data = er_data ).


        ELSE.

          lo_container->add_messages_from_bapi(
             it_bapi_messages          =   lt_return               " Return parameter table
          ).

          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              message_container = lo_container.

        ENDIF.

      WHEN 'SubscribetoAlerts'.
        DATA(lv_mail) =  it_parameter[ name = 'email' ]-value.
        sns_subscription( lv_mail ).
        ls_return-msg = |Subscription was created successfully|.

         me->copy_data_to_ref(
           EXPORTING
           is_data = ls_return
           CHANGING
           cr_data = er_data ).


      WHEN 'Discard'.
        lv_invoice_key =  it_parameter[ name = 'InvoiceNumber' ]-value.

        IMPORT expenses = lt_expenses FROM DATABASE indx(zp) ID lv_index_id
               ACCEPTING PADDING.

        LOOP AT lt_expenses ASSIGNING <fs_expense>.
          at_expense_summary = <fs_expense>-expense_summary.

          remove_duplicates_by_score( ).
          TRY.
              IF  at_expense_summary[
                          expense_type = 'INVOICE_RECEIPT_ID' ]-value EQ
                       lv_invoice_key.
                DELETE lt_expenses where bucket_key = <fs_expense>-bucket_key.
              ENDIF.

            CATCH cx_sy_itab_line_not_found.
              CONTINUE.
          ENDTRY.
        ENDLOOP.
* export
        EXPORT expenses = lt_expenses TO DATABASE indx(zp) ID lv_index_id
              FROM ls_indx COMPRESSION ON.
* store all the invoices for auditing
        create_audit_indx( lt_expenses ).

        ls_return-belnr = lv_invoice_key.

            me->copy_data_to_ref(
           EXPORTING
           is_data = ls_return
           CHANGING
           cr_data = er_data ).


      WHEN OTHERS.


    ENDCASE.

  ENDMETHOD.


  METHOD /iwbep/if_mgw_appl_srv_runtime~get_expanded_entity.

    DATA: ls_deep_entity TYPE zcl_zinvoice_app_mpc_ext=>ty_deep_invoice.
    DATA lv_index_id        TYPE char22.
    DATA lt_expenses        TYPE zcl_aws_textract_helper=>tt_expenses.

    lv_index_id        = |AP-{ sy-uname }|.

** Get the key value
    TRY.
        DATA(lv_key)       = it_key_tab[ name = 'invoiceNumber' ]-value.
      CATCH cx_sy_itab_line_not_found.
        DATA(lt_key_tab) = io_tech_request_context->get_keys( ).

        IF NOT lt_key_tab IS INITIAL.
          TRY.
              lv_key = lt_key_tab[ name = 'XBLNR' ]-value.
            CATCH cx_sy_itab_line_not_found.
          ENDTRY.
        ENDIF.
    ENDTRY.

** import the invoices
    IMPORT expenses = lt_expenses
           FROM DATABASE indx(zp) ID lv_index_id
           ACCEPTING PADDING.

    IF sy-subrc = 0.

      LOOP AT lt_expenses INTO DATA(ls_expenses).
        at_expense_summary = ls_expenses-expense_summary.
        remove_duplicates_by_score( ).

        IF  get_value_expensetype( 'INVOICE_RECEIPT_ID' ) = lv_key.

          DATA(lv_found) = abap_true.

          convert_items(
            EXPORTING
              ie_key   = lv_key
              ie_items =  ls_expenses-expense_items
            IMPORTING
               re_items = DATA(lt_items)
          ).

          ls_deep_entity = VALUE  #(
                                    xblnr = get_value_expensetype( 'INVOICE_RECEIPT_ID' )
                                    lifnr = get_value_expensetype( 'ACCOUNT_NUMBER' )
                                    budat = get_value_expensetype( 'INVOICE_RECEIPT_DATE' )
                                    kudat = get_value_expensetype( 'DUE_DATE' )
                                    name  = get_value_expensetype( 'VENDOR_NAME' )
                                    name1 = get_value_expensetype( 'VENDOR_ADDRESS' )
                                    wrbtr = get_value_expensetype( 'TOTAL' )
                                    waers = get_currency_for_expensetype( 'TOTAL' )
                                    score = get_overall_summary_score( )
                                    status = ls_expenses-status
                                    belnr  = ls_expenses-belnr
                                    path   = |{ ls_expenses-bucket }/{ ls_expenses-bucket_key }|
                                    toitems = lt_items
                                     ).



        ENDIF.
      ENDLOOP.

      IF lv_found = abap_false.

        mo_context->get_message_container( )->add_message_text_only(
          EXPORTING
            iv_msg_type               = mo_context->get_message_container( )->gcs_message_type-error
            iv_msg_text               = |No Invoice found for key { lv_key }|                 " Message Text
            iv_entity_type            = iv_entity_name                 " Entity type/name

        ).

        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message_container = mo_context->get_message_container( ).

      ELSE.

        copy_data_to_ref(
          EXPORTING
            is_data =  ls_deep_entity
          CHANGING
            cr_data = er_entity
        ).

        APPEND 'TOITEMS' TO et_expanded_tech_clauses.

      ENDIF.

    ELSE.

      mo_context->get_message_container( )->add_message_text_only(
         EXPORTING
           iv_msg_type               = mo_context->get_message_container( )->gcs_message_type-error
           iv_msg_text               = |No Invoice found for key { lv_key }|                 " Message Text
           iv_entity_type            = iv_entity_name                 " Entity type/name

       ).

      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          message_container = mo_context->get_message_container( ).

    ENDIF.

  ENDMETHOD.


  METHOD /iwbep/if_mgw_appl_srv_runtime~get_stream.

    DATA lt_expenses        TYPE zcl_aws_textract_helper=>tt_expenses.
    DATA lv_index_id        TYPE char22.
    DATA ls_stream          TYPE ty_s_media_resource.

    DATA ls_header TYPE ihttpnvp.

    lv_index_id        = |AP-{ sy-uname }|.


    TRY.
        DATA(lv_key)       = it_key_tab[ name = 'InvoiceNumber' ]-value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
** import the invoices
    IMPORT expenses = lt_expenses
           FROM DATABASE indx(zp) ID lv_index_id
           ACCEPTING PADDING.

    IF sy-subrc = 0.

      get_profile_user( ).

      LOOP AT lt_expenses INTO DATA(ls_expenses).
        at_expense_summary = ls_expenses-expense_summary.
        remove_duplicates_by_score( ).
        IF  get_value_expensetype( 'INVOICE_RECEIPT_ID' ) = lv_key.

          DATA(lo_s3) = NEW zcl_aws_s3_helper( im_profile = gv_profile ).

          CALL METHOD lo_s3->get_object
            EXPORTING
              im_bucket = ls_expenses-bucket
              im_key    = ls_expenses-bucket_key
            IMPORTING
              re_data   = DATA(lv_data)
              re_mime   = DATA(lv_mime_type).

          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_data IS NOT INITIAL.
        ls_stream-mime_type = lv_mime_type.
        ls_stream-value = lv_data.
        ls_header-name = 'Content-Disposition'.
        ls_header-value = |inline; filename={ ls_expenses-bucket_key }|.

        set_header( ls_header ).

        me->copy_data_to_ref(
        EXPORTING
        is_data = ls_stream
        CHANGING
        cr_data = er_stream ).



      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD analyze_invoice_textract.

    DATA lt_expense_history TYPE zcl_aws_textract_helper=>tt_expenses.
    DATA lt_expenses        TYPE zcl_aws_textract_helper=>tt_expenses.
    DATA lv_index_id        TYPE char22.
    DATA lv_exists          TYPE c.

    DATA lc_guid TYPE REF TO cl_abap_random_packed.
    DATA lv_seed TYPE i.
    DATA lv_guid TYPE p.

    lv_index_id        = |AP-{ sy-uname }|.

    get_profile_user( ).

    DATA(lo_textract_helper) = NEW zcl_aws_textract_helper( gv_profile ).

    lo_textract_helper->set_min_score( 90 ).
** synch or aysnch
    SELECT SINGLE low FROM tvarv INTO @DATA(lv_asynch)
                   WHERE name = 'TEXTRACT_ASYNCH'.

    CASE lv_asynch.

      WHEN abap_false.

        TRY.
            lt_expenses = lo_textract_helper->analyze_expense(
                                        EXPORTING
                                          iv_bucket  = im_bucket
                                          iv_key     = im_key
                                      ).

          CATCH  /aws1/cx_texaccessdeniedex.
          CATCH  /aws1/cx_texbaddocumentex.
          CATCH /aws1/cx_texdocumenttoolargeex.
          CATCH /aws1/cx_texinternalservererr.
          CATCH /aws1/cx_texinvalidparameterex.
          CATCH /aws1/cx_texinvalids3objectex.
          CATCH /aws1/cx_texprovthruputexcdex.
          CATCH /aws1/cx_texthrottlingex.
          CATCH /aws1/cx_texunsupporteddocex.
          CATCH /aws1/cx_texclientexc.
          CATCH /aws1/cx_texserverexc.
          CATCH /aws1/cx_rt_technical_generic.
          CATCH /aws1/cx_rt_service_generic.
        ENDTRY.

      WHEN abap_true.
        DATA(lv_jobid) = lo_textract_helper->analyze_expense_asynch(
                                            EXPORTING
                                             iv_bucket = im_bucket
                                             iv_key    = im_key
                                             ).
        IF lv_jobid IS NOT INITIAL.
          TRY.
              CALL METHOD lo_textract_helper->get_expense_results_asynch
                EXPORTING
                  im_jobid    = lv_jobid
                IMPORTING
                  re_status   = DATA(lv_status)
                  rt_expenses = lt_expenses.

            CATCH  /aws1/cx_texaccessdeniedex.
            CATCH /aws1/cx_texinternalservererr.
            CATCH  /aws1/cx_texinvalidjobidex.
            CATCH /aws1/cx_texinvalidkmskeyex.
            CATCH /aws1/cx_texinvalidparameterex.
            CATCH  /aws1/cx_texinvalids3objectex.
            CATCH  /aws1/cx_texprovthruputexcdex.
            CATCH /aws1/cx_texthrottlingex.
            CATCH /aws1/cx_texclientexc.
            CATCH /aws1/cx_texserverexc.
            CATCH /aws1/cx_rt_technical_generic.
            CATCH /aws1/cx_rt_service_generic.

          ENDTRY.

        ENDIF.
    ENDCASE.



* check invoice without receipt ID
    LOOP AT lt_expenses INTO DATA(ls_expenses).
      at_expense_summary = ls_expenses-expense_summary.
      remove_duplicates_by_score( ).
      READ TABLE  ls_expenses-expense_summary WITH KEY
                  expense_type = 'INVOICE_RECEIPT_ID'
                  TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        lv_exists = abap_false.
      ELSE.
        lv_exists = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.


** Random seed generator
  CALL METHOD cl_abap_random=>seed
    RECEIVING
      seed   = lv_seed.

  CALL METHOD cl_abap_random_packed=>create
   EXPORTING
      seed   = lv_seed
      min    = 100000000
      max    = 999999999
    RECEIVING
      prng   = lc_guid.



    IF lv_exists = abap_false.
      READ TABLE lt_expenses assigning field-symbol(<fs_expense>) INDEX 1.
      IF sy-subrc = 0.
        IF <fs_expense>-expense_summary[] IS NOT INITIAL.
          APPEND INITIAL LINE TO <fs_expense>-expense_summary ASSIGNING
                         FIELD-SYMBOL(<fs_summary>).
** assign a transaction id
         <fs_summary>-expense_type = 'INVOICE_RECEIPT_ID'.
          <fs_summary>-value =  lc_guid->get_next( ).
          condense <fs_summary>-value.
         <fs_summary>-score = 95.
         <fs_summary>-noreceipt = 'X'.
        ENDIF.
      ENDIF.
    ENDIF.


    IF lt_expenses IS INITIAL.
      RAISE textract_error.
    ENDIF.


    DATA(ls_indx) = VALUE indx( aedat = sy-datum
                                usera = sy-uname ).

*import invoices for this user before exporting
    IMPORT expenses = lt_expense_history FROM DATABASE indx(zp) ID lv_index_id
          ACCEPTING PADDING.

    IF sy-subrc = 0.
* handle duplicates
      LOOP AT lt_expense_history INTO DATA(ls_history).
        LOOP AT lt_expenses INTO ls_expenses.

          at_expense_summary = ls_expenses-expense_summary.

          remove_duplicates_by_score( ).

          TRY.
              IF  ls_expenses-expense_summary[
                          expense_type = 'INVOICE_RECEIPT_ID' ]-value EQ
                   ls_history-expense_summary[
                          expense_type = 'INVOICE_RECEIPT_ID' ]-value.

                RAISE duplicate_invoice.
              ENDIF.
            CATCH cx_sy_itab_line_not_found.
              CONTINUE.
          ENDTRY.
        ENDLOOP.
      ENDLOOP.

      APPEND LINES OF lt_expense_history TO lt_expenses.
      SORT lt_expenses BY aedtm DESCENDING.
    ENDIF.
* export
    EXPORT expenses = lt_expenses TO DATABASE indx(zp) ID lv_index_id
          FROM ls_indx COMPRESSION ON.

* store all the invoices for auditing
    create_audit_indx( lt_expenses ).


  ENDMETHOD.


  METHOD convert_items.

    LOOP AT ie_items INTO DATA(ls_items).
      APPEND INITIAL LINE TO re_items ASSIGNING FIELD-SYMBOL(<fs_items>).
       <fs_items>-xblnr = ie_key.
      <fs_items>-posnr = ls_items-posnr.
      <fs_items>-matnr = ls_items-product_code.
      <fs_items>-desc = ls_items-description.
      <fs_items>-qty = ls_items-quantity.
      <fs_items>-unit = ls_items-unit_price.
      <fs_items>-total = ls_items-price.
    ENDLOOP.
  ENDMETHOD.


  METHOD create_audit_indx.
    DATA lt_expense_audit_history TYPE zcl_aws_textract_helper=>tt_expenses.
    DATA(ls_indx) = VALUE indx( aedat = sy-datum
                                  usera = sy-uname ).
* retreive history
    IMPORT expenses = lt_expense_audit_history FROM DATABASE indx(zp) ID 'AUDIT'
      ACCEPTING PADDING.
* add new data
    APPEND LINES OF it_expense TO lt_expense_audit_history.
* update teh audit table
    EXPORT expenses = lt_expense_audit_history TO DATABASE indx(zp) ID 'AUDIT'
            FROM ls_indx COMPRESSION ON.

  ENDMETHOD.


  method GET_CURRENCY_FOR_EXPENSETYPE.

    read table at_expense_summary into data(ls_expense_summary)
                                  with key expense_type = ie_type.
    if sy-subrc = 0.
      case ie_type.
        when 'TOTAL'.
          re_value = ls_expense_summary-currency.
       when others..

      endcase.

    endif.

  endmethod.


  METHOD get_overall_summary_score.

    IF at_expense_summary IS NOT INITIAL.
      LOOP AT at_expense_summary INTO DATA(ls_expense_summary).
        IF  ls_expense_summary-noreceipt = 'X'.
          DATA(lv_missing_receipt) = abap_true.
        ENDIF.
        re_score = re_score + ls_expense_summary-score.
      ENDLOOP.

      IF lv_missing_receipt = abap_true.

        re_score = 90.

      ELSE.
        re_score = re_score / lines( at_expense_summary ).
      ENDIF.
    ENDIF.
  ENDMETHOD.


METHOD get_profile_user.


  SELECT profile_id UP TO 1 ROWS FROM /aws1/rt_pflh INTO
         gv_profile WHERE description = sy-uname
         ORDER BY PRIMARY KEY.
  ENDSELECT.

  IF sy-subrc = 0.
    IF to_upper( sy-uname ) CA sy-abcde.
      gv_profile = 'DEMO'.
    ENDIF.
    else.
      gv_profile = 'DEMO'.
  ENDIF.

ENDMETHOD.


  method GET_VALUE_EXPENSETYPE.

    read table at_expense_summary into data(ls_expense_summary)
                                  with key expense_type = ie_type.
    if sy-subrc = 0.
      case ie_type.
        when 'TOTAL'.
          replace all occurrences of regex '[^\d.]' in ls_expense_summary-value
                      with space.
          condense ls_expense_summary-value.

          re_value = ls_expense_summary-value.
       when others.
      re_value = ls_expense_summary-value.

      endcase.

    endif.

  endmethod.


  METHOD invoices_get_entity.

    DATA lv_index_id        TYPE char22.
    DATA lt_expenses        TYPE zcl_aws_textract_helper=>tt_expenses.
** Get index id
    lv_index_id        = |AP-{ sy-uname }|.
** Get the key value
    TRY.
        DATA(lv_key)       = it_key_tab[ name = 'invoiceNumber' ]-value.
      CATCH cx_sy_itab_line_not_found.
        DATA(lt_key_tab) = io_tech_request_context->get_keys( ).

        IF NOT lt_key_tab IS INITIAL.
          TRY.
              lv_key = lt_key_tab[ name = 'XBLNR' ]-value.
            CATCH cx_sy_itab_line_not_found.
          ENDTRY.
        ENDIF.
    ENDTRY.



** import the invoices
    IMPORT expenses = lt_expenses
           FROM DATABASE indx(zp) ID lv_index_id
           ACCEPTING PADDING.

    IF sy-subrc = 0.

      LOOP AT lt_expenses INTO DATA(ls_expenses).
        at_expense_summary = ls_expenses-expense_summary.

        remove_duplicates_by_score( ).

        IF  get_value_expensetype( 'INVOICE_RECEIPT_ID' ) = lv_key.

          DATA(lv_found) = abap_true.

          er_entity = VALUE #(      xblnr = get_value_expensetype( 'INVOICE_RECEIPT_ID' )
                                    lifnr = get_value_expensetype( 'ACCOUNT_NUMBER' )
                                    budat = get_value_expensetype( 'INVOICE_RECEIPT_DATE' )
                                    kudat = get_value_expensetype( 'DUE_DATE' )
                                    name  = get_value_expensetype( 'VENDOR_NAME' )
                                    name1 = get_value_expensetype( 'VENDOR_ADDRESS' )
                                    wrbtr = get_value_expensetype( 'TOTAL' )
                                    waers = get_currency_for_expensetype( 'TOTAL' )
                                    score = get_overall_summary_score( )
                                    status = ls_expenses-status
                                    belnr  = ls_expenses-belnr
                                    path   = |{ ls_expenses-bucket }/{ ls_expenses-bucket_key }|
                                     ).

        ENDIF.
      ENDLOOP.

      IF lv_found = abap_false.

        mo_context->get_message_container( )->add_message_text_only(
          EXPORTING
            iv_msg_type               = mo_context->get_message_container( )->gcs_message_type-error
            iv_msg_text               = |No Invoice found for key { lv_key }|                 " Message Text
            iv_entity_type            = iv_entity_name                 " Entity type/name

        ).

        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message_container = mo_context->get_message_container( ).

      ENDIF.

    ELSE.

      mo_context->get_message_container( )->add_message_text_only(
         EXPORTING
           iv_msg_type               = mo_context->get_message_container( )->gcs_message_type-error
           iv_msg_text               = |No Invoice found for key { lv_key }|                 " Message Text
           iv_entity_type            = iv_entity_name                 " Entity type/name

       ).

      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          message_container = mo_context->get_message_container( ).

    ENDIF.

  ENDMETHOD.


  METHOD invoices_get_entityset.

    DATA lv_index_id        TYPE char22.
    DATA lt_expenses        TYPE zcl_aws_textract_helper=>tt_expenses.

    lv_index_id        = |AP-{ sy-uname }|.

   if it_key_tab is not initial.

   endif.

    IMPORT expenses = lt_expenses
           FROM DATABASE indx(zp) ID lv_index_id
           ACCEPTING PADDING.

    IF sy-subrc = 0.
      IF  io_tech_request_context->has_count( ).
          es_response_context-count = lines( lt_expenses ).
      ELSE.


        LOOP AT lt_expenses INTO DATA(ls_expenses).
          at_expense_summary =  ls_expenses-expense_summary.

          remove_duplicates_by_score( ).

          et_entityset = VALUE #( BASE et_entityset
                                  ( xblnr = get_value_expensetype( 'INVOICE_RECEIPT_ID' )
                                    lifnr = get_value_expensetype( 'ACCOUNT_NUMBER' )
                                    budat = get_value_expensetype( 'INVOICE_RECEIPT_DATE' )
                                    kudat = get_value_expensetype( 'DUE_DATE' )
                                    name  = get_value_expensetype( 'VENDOR_NAME' )
                                    name1 = get_value_expensetype( 'VENDOR_ADDRESS' )
                                    wrbtr = get_value_expensetype( 'TOTAL' )
                                    waers = get_currency_for_expensetype( 'TOTAL' )
                                    score = get_overall_summary_score( )
                                    status = ls_expenses-status
                                    belnr  = ls_expenses-belnr
                                    path   = |{ ls_expenses-bucket }/{ ls_expenses-bucket_key }|
                                     ) ).

        ENDLOOP.

      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD post_invoice.

    DATA: ls_header       TYPE           bapiache09.
    DATA: ls_cpd          TYPE           bapiacpa09.
    DATA: lt_accountgl    TYPE TABLE OF  bapiacgl09.
    DATA: lt_vendoritem   TYPE TABLE OF  bapiacap09.
    DATA: lt_amount       TYPE TABLE OF  bapiaccr09.

    DATA: lv_vendor_total TYPE bapidoccur.
    DATA: lv_item_total   TYPE bapidoccur.
    DATA: lv_posnr        TYPE posnr_acc.
    DATA: lv_key          TYPE bapiache09-obj_key.
    DATA: lt_return       TYPE TABLE OF bapiret2.

    DATA: lv_trans_desc   TYPE string.
    DATA: lv_item(3)      TYPE n.
    DATA: lv_msg     TYPE string,
          lv_subject TYPE string.

    ls_header-comp_code = '1710'.
    ls_header-doc_type  = 'KR'.
    ls_header-username  = sy-uname.
    ls_header-ref_doc_no = get_value_expensetype( 'INVOICE_RECEIPT_ID' ).

    DATA: lv_date_string TYPE string,
          lv_date_internal TYPE sy-datum.
    
    lv_date_string = get_value_expensetype( 'INVOICE_RECEIPT_DATE' ).
    
    " Handle different date formats from Textract
    IF lv_date_string IS NOT INITIAL.
      " Try to convert various date formats
      IF lv_date_string CO '0123456789/'.
        " Format: MM/DD/YYYY or DD/MM/YYYY
        REPLACE ALL OCCURRENCES OF '/' IN lv_date_string WITH ''.
        IF strlen( lv_date_string ) = 8.
          " Assume MMDDYYYY format, convert to YYYYMMDD
          lv_date_internal = |{ lv_date_string+4(4) }{ lv_date_string+0(2) }{ lv_date_string+2(2) }|.
        ENDIF.
      ELSEIF lv_date_string CO '0123456789-'.
        " Format: YYYY-MM-DD
        REPLACE ALL OCCURRENCES OF '-' IN lv_date_string WITH ''.
        IF strlen( lv_date_string ) = 8.
          lv_date_internal = lv_date_string.
        ENDIF.
      ELSEIF lv_date_string CO '0123456789.'.
        " Format: DD.MM.YYYY
        REPLACE ALL OCCURRENCES OF '.' IN lv_date_string WITH ''.
        IF strlen( lv_date_string ) = 8.
          lv_date_internal = |{ lv_date_string+4(4) }{ lv_date_string+2(2) }{ lv_date_string+0(2) }|.
        ENDIF.
      ENDIF.
      
      " Validate the converted date
      CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
        EXPORTING
          date                      = lv_date_internal
        EXCEPTIONS
          plausibility_check_failed = 1
          OTHERS                    = 2.
      
      IF sy-subrc = 0.
        ls_header-doc_date = lv_date_internal.
      ELSE.
        " If conversion fails, use current date as fallback
        ls_header-doc_date = sy-datum.
      ENDIF.
    ELSE.
      " If no date found, use current date
      ls_header-doc_date = sy-datum.
    ENDIF.

    ls_header-pstng_date = sy-datum.

* Gl items
    LOOP AT ie_expense-expense_items INTO DATA(ls_items).

      lv_posnr = lv_posnr + 1.
      APPEND INITIAL LINE TO  lt_accountgl ASSIGNING FIELD-SYMBOL(<fs_gl>).
      <fs_gl>-itemno_acc = lv_posnr.
      <fs_gl>-gl_account = '0012119200'.
      <fs_gl>-item_text  = ls_items-description.

      APPEND INITIAL LINE TO  lt_amount ASSIGNING FIELD-SYMBOL(<fs_amt>).
      <fs_amt>-itemno_acc =   lv_posnr.
      <fs_amt>-currency   = 'USD'.
      <fs_amt>-amt_doccur = <fs_amt>-amt_doccur +  ls_items-price.
      lv_item_total = lv_item_total + <fs_amt>-amt_doccur.
    ENDLOOP.
* vendor item
    lv_posnr = lv_posnr + 1.
    lv_vendor_total =    get_value_expensetype( 'TOTAL' ).
* Tax/others
    IF lv_vendor_total - lv_item_total > 0.
      APPEND INITIAL LINE TO  lt_accountgl ASSIGNING <fs_gl>.
      <fs_gl>-itemno_acc = lv_posnr.
      <fs_gl>-gl_account = '0012119200'.
      <fs_gl>-item_text  = 'Tax/Others'.

      APPEND INITIAL LINE TO  lt_amount ASSIGNING <fs_amt>.
      <fs_amt>-itemno_acc =   lv_posnr.
      <fs_amt>-currency   = 'USD'.
      <fs_amt>-amt_doccur = lv_vendor_total - lv_item_total.
      lv_posnr = lv_posnr + 1.
    ENDIF.


    APPEND INITIAL LINE TO  lt_vendoritem ASSIGNING FIELD-SYMBOL(<fs_vendor>).
    <fs_vendor>-itemno_acc = lv_posnr.
    <fs_vendor>-vendor_no  = '0017300273'.

    APPEND INITIAL LINE TO  lt_amount ASSIGNING <fs_amt>.
    <fs_amt>-itemno_acc =   lv_posnr.
    <fs_amt>-currency   = 'USD'.
    <fs_amt>-amt_doccur = lv_vendor_total * -1.

    ls_cpd-name =  get_value_expensetype( 'VENDOR_NAME' ).
    ls_cpd-city = 'ONET'.

    CALL FUNCTION 'BAPI_ACC_DOCUMENT_POST'
      EXPORTING
        documentheader = ls_header
        customercpd    = ls_cpd
      IMPORTING
        obj_key        = lv_key               " Reference key
      TABLES
        accountgl      = lt_accountgl         " G/L account item
        accountpayable = lt_vendoritem        " Vendor Item
        currencyamount = lt_amount
        return         = lt_return.           " Return parameter

    IF line_exists( lt_return[ type = 'E' ] ).
     et_return = lt_return.
    ELSE.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'.

        ee_key = lv_key(10).
** fire SNS notification
       send_notification( ee_key ).

** translate descriptions
        LOOP AT ie_expense-expense_items into ls_items.
         lv_item = lv_item + 1.

         translate_description( ie_key = ee_key
                                ie_description = ls_items-description
                                ie_item = lv_item ).
        endloop.

    ENDIF.

  ENDMETHOD.


  METHOD remove_duplicates_by_score.

    SORT at_expense_summary BY expense_type ASCENDING page ASCENDING score DESCENDING.

    DELETE ADJACENT DUPLICATES FROM
                     at_expense_summary COMPARING expense_type.

  ENDMETHOD.


  METHOD items_get_entityset.
    DATA lv_index_id        TYPE char22.
    DATA lt_expenses        TYPE zcl_aws_textract_helper=>tt_expenses.
    DATA lv_invoice_id      TYPE string.

    lv_index_id        = |AP-{ sy-uname }|.


    TRY.
        DATA(lv_key)       = it_key_tab[ name = 'invoiceNumber' ]-value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.


** import the invoices
    IMPORT expenses = lt_expenses
           FROM DATABASE indx(zp) ID lv_index_id
           ACCEPTING PADDING.

    IF sy-subrc = 0.

      LOOP AT lt_expenses INTO DATA(ls_expenses).
        at_expense_summary = ls_expenses-expense_summary.
        remove_duplicates_by_score( ).

        lv_invoice_id =  get_value_expensetype( 'INVOICE_RECEIPT_ID' ).

        if lv_key is not initial.
          check lv_invoice_id = lv_key.
        endif.

        convert_items(
          EXPORTING
            ie_key   = lv_invoice_id
            ie_items =  ls_expenses-expense_items
          IMPORTING
             re_items = DATA(lt_items)
        ).

        APPEND LINES OF lt_items TO et_entityset. CLEAR: lt_items.

      ENDLOOP.

      IF et_entityset IS INITIAL.

        mo_context->get_message_container( )->add_message_text_only(
          EXPORTING
            iv_msg_type               = mo_context->get_message_container( )->gcs_message_type-error
            iv_msg_text               = |No Invoice found for key { lv_key }|                 " Message Text
            iv_entity_type            = iv_entity_name                 " Entity type/name

        ).

        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message_container = mo_context->get_message_container( ).

      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD save_item_text.


    DATA: ls_head TYPE thead.
    DATA: lv_desc TYPE string.
    DATA: lt_lines TYPE TABLE OF tline.


    CALL FUNCTION 'CONVERSION_EXIT_ISOLA_INPUT'
      EXPORTING
        input            = ie_langu
      IMPORTING
        output           = ls_head-tdspras
      EXCEPTIONS
        unknown_language = 1
        OTHERS           = 2.

    ls_head-tdname = |{ gv_bukrs }|    &&
                     |{ ie_key }| &&
                     |{ gv_year }|    &&
                     |{ ie_item }|.

    ls_head-tdobject = 'DOC_ITEM'.
    ls_head-tdid     = '0001'.

    lv_desc = ie_description  .


    IF strlen( lv_desc ) <= 132.
      APPEND INITIAL LINE TO lt_lines
          ASSIGNING FIELD-SYMBOL(<fs_line>).
      <fs_line>-tdformat = '*'.
      <fs_line>-tdline = lv_desc.
    ELSE.
      DO.
        APPEND INITIAL LINE TO lt_lines
        ASSIGNING <fs_line>.
        IF sy-index = 1.
          <fs_line>-tdformat = '*'.
        ELSE.
          <fs_line>-tdformat = '='.
        ENDIF.

        IF strlen( lv_desc ) > 132.
          <fs_line>-tdline = lv_desc(132).
          lv_desc = lv_desc+132.
        ELSE.
          <fs_line>-tdline = lv_desc.
          EXIT.
        ENDIF.
      ENDDO.
    ENDIF.



    CALL FUNCTION 'SAVE_TEXT'
      EXPORTING
        header          = ls_head
        insert          = 'I'
        savemode_direct = 'X'
      TABLES
        lines           = lt_lines
      EXCEPTIONS
        id              = 1
        language        = 2
        name            = 3
        object          = 4
        OTHERS          = 5.

    IF sy-subrc = 0.
      COMMIT WORK.
    ENDIF.

  ENDMETHOD.


  METHOD send_notification.


    get_profile_user( ).

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create(
                                               iv_profile_id =  gv_profile  ).

    DATA(lo_sns)     = /aws1/cl_sns_factory=>create( lo_session ).
    DATA(lt_topics) = lo_sns->listtopics( )->get_topics( ).

    LOOP AT lt_topics INTO DATA(ls_topic).

      DATA(lt_attributes) =  lo_sns->gettopicattributes(
            iv_topicarn =  ls_topic->get_topicarn( )
        )->get_attributes( ).
* Create a subscription to the topic
      READ TABLE lt_attributes WITH KEY key = 'TopicArn'
             INTO DATA(ls_attributes).
      IF sy-subrc = 0.
        IF ls_attributes-value->get_value( ) CS 'ap-notifications'.

          lo_sns->publish(
              iv_topicarn               = ls_attributes-value->get_value( )
              iv_message                 = |Accounting document { ie_key } was posted successfully in company code 1710|
              iv_subject                 = |Accounts payable alerts |
          ).

        ENDIF.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD sns_subscription.

    get_profile_user( ).

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create(
                                               iv_profile_id =  gv_profile ).

    DATA(lo_sns)     = /aws1/cl_sns_factory=>create( lo_session ).

    TRY.
        DATA(lv_topic_arn) =   lo_sns->createtopic(
             EXPORTING
               iv_name                 = 'ap-notifications'
           )->get_topicarn( ).
      CATCH /aws1/cx_snsautherrorexception. " AuthorizationErrorException
      CATCH /aws1/cx_snsconcurrentaccessex. " ConcurrentAccessException
      CATCH /aws1/cx_snsinternalerrorex.    " InternalErrorException
      CATCH /aws1/cx_snsinvalidparameterex. " InvalidParameterException
      CATCH /aws1/cx_snsinvalidsecurityex.  " InvalidSecurityException
      CATCH /aws1/cx_snsstaletagexception.  " StaleTagException
      CATCH /aws1/cx_snstaglimitexceededex. " TagLimitExceededException
      CATCH /aws1/cx_snstagpolicyexception. " TagPolicyException
      CATCH /aws1/cx_snstopiclimitexcdex.   " TopicLimitExceededException
      CATCH /aws1/cx_snsclientexc.          " Exception /AWS1/CX_SNSCLIENTEXC
      CATCH /aws1/cx_snsserverexc.          " Exception /AWS1/CX_SNSSERVEREXC
      CATCH /aws1/cx_rt_technical_generic.  " Technical errors
      CATCH /aws1/cx_rt_service_generic.    " Generic Service call error
    ENDTRY.


    TRY.
        lo_sns->subscribe(
          EXPORTING
             iv_topicarn              =  lv_topic_arn
             iv_protocol              =  'Email'
             iv_endpoint              = ie_mail
        ).
      CATCH /aws1/cx_snsautherrorexception. " AuthorizationErrorException
      CATCH /aws1/cx_snsfiltplylimitexcdex. " FilterPolicyLimitExceededException
      CATCH /aws1/cx_snsinternalerrorex.    " InternalErrorException
      CATCH /aws1/cx_snsinvalidparameterex. " InvalidParameterException
      CATCH /aws1/cx_snsinvalidsecurityex.  " InvalidSecurityException
      CATCH /aws1/cx_snsnotfoundexception.  " NotFoundException
      CATCH /aws1/cx_snsreplaylimitexcdex.  " ReplayLimitExceededException
      CATCH /aws1/cx_snssubscriptionlmte00. " SubscriptionLimitExceededException
      CATCH /aws1/cx_snsclientexc.          " Exception /AWS1/CX_SNSCLIENTEXC
      CATCH /aws1/cx_snsserverexc.          " Exception /AWS1/CX_SNSSERVEREXC
      CATCH /aws1/cx_rt_technical_generic.  " Technical errors
      CATCH /aws1/cx_rt_service_generic.    " Generic Service call error
    ENDTRY.


  ENDMETHOD.


  METHOD translate_description.

    get_profile_user( ).

* Session
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( iv_profile_id = gv_profile ).
* Translate
    DATA(lo_xl8)     = /aws1/cl_xl8_factory=>create( lo_session ).
* Translate
    CALL METHOD lo_xl8->translatetext
      EXPORTING
        iv_text               = ie_description
        iv_sourcelanguagecode = 'auto'    " will use comprehend to do lang detection
        iv_targetlanguagecode = 'de'
      RECEIVING
        oo_output             = DATA(lo_output).


    DATA(lv_trans_desc) = lo_output->get_translatedtext( ).

    save_item_text( ie_key = ie_key
                    ie_description = ie_description
                    ie_item = ie_item
                    ie_langu = 'EN' ).

    save_item_text( ie_key = ie_key
                ie_description = lv_trans_desc
                ie_item = ie_item
                ie_langu = 'DE' ).

  ENDMETHOD.


  METHOD write_data_to_s3.

    DATA: lo_client_proxy    TYPE REF TO /iwbep/if_cp_client_proxy,
          lo_entity_resource TYPE REF TO /iwbep/if_cp_resource_entity,
          lo_read_request    TYPE REF TO /iwbep/if_cp_request_read,
          lo_read_response   TYPE REF TO /iwbep/if_cp_response_read.

    DATA:  ls_invoice TYPE zcl_zinvoice_app_mpc_ext=>ty_deep_invoice.

    DATA: lv_date TYPE sy-datum.

    TYPES: BEGIN OF ty_key,
             xblnr TYPE xblnr,
           END OF ty_key.

    DATA: BEGIN OF ls_invoice_csv,
            BusinessCode             TYPE string,
            SupplierID               TYPE string,
            SupplierName             TYPE string,
            ItemID                   TYPE string,
            ItemDescription          TYPE string,
            DueDateOfInvoice(10)     TYPE c,
            BusinessYear             TYPE string,
            InvoiceDate(10)          TYPE c,
            AccountingDocumentID     TYPE string,
            DocumentCreationDate(10) TYPE c,
            Comments                 TYPE string,
            Status                   TYPE string,
            InvoiceAmount            TYPE string,
            DocumentCurrency         TYPE string,
          END OF ls_invoice_csv.

    DATA: lt_invoice_csv LIKE TABLE OF ls_invoice_csv.

    DATA: lt_conv_data TYPE truxs_t_text_data.
    DATA: lv_string  TYPE string,
          lv_xstring TYPE xstring.

    TRY.
        lo_client_proxy = /iwbep/cl_cp_client_proxy_fact=>create_v2_local_proxy( VALUE #( service_id      = 'ZINVOICE_APP_SRV'
                                                                                             service_version = '0001' ) ).

        lo_entity_resource =
        lo_client_proxy->create_resource_for_entity_set( 'Invoices' )->navigate_with_key( VALUE ty_key( xblnr = ie_key ) ).
        lo_read_request = lo_entity_resource->create_request_for_read( ).
        DATA(lo_expand) = lo_read_request->create_expand_node( ).
        lo_expand->add_expand( 'TOITEMS' ).
        lo_read_request->set_expand( lo_expand ).

        lo_read_response = lo_read_request->execute( ).

        lo_read_response->get_business_data(
          IMPORTING
             es_business_data = ls_invoice ).


      CATCH /iwbep/cx_gateway INTO DATA(lx_gateway).


    ENDTRY.


    LOOP AT ls_invoice-toitems INTO DATA(ls_items).
      ls_invoice_csv-businesscode = '1710'.
      ls_invoice_csv-supplierid = '17300273'.
      ls_invoice_csv-suppliername = ls_invoice-name.
      ls_invoice_csv-itemid = ls_items-matnr.

      REPLACE ALL OCCURENCES OF '"' IN ls_invoice_csv-itemid WITH '""'.
      ls_invoice_csv-itemdescription = ls_items-desc.


      REPLACE ALL OCCURENCES OF '"' IN ls_invoice_csv-itemdescription WITH '""'.
      WRITE sy-datum TO ls_invoice_csv-documentcreationdate MM/DD/YYYY.

      CALL FUNCTION 'CONVERT_DATE_TO_INTERNAL'
        EXPORTING
          date_external            = ls_invoice-budat
        IMPORTING
          date_internal            = lv_date
        EXCEPTIONS
          date_external_is_invalid = 1
          OTHERS                   = 2.

      ls_invoice_csv-businessyear = lv_date+0(4).
      WRITE lv_date TO ls_invoice_csv-DueDateOfInvoice MM/DD/YYYY.
      WRITE lv_date TO ls_invoice_csv-invoicedate MM/DD/YYYY.
      ls_invoice_csv-AccountingDocumentID = ls_invoice-belnr.
      ls_invoice_csv-Comments = |Late payment due to missed submission by vendor verification in progress|.
      ls_invoice_csv-status = 'Pending'.
      ls_invoice_csv-invoiceamount = ls_items-total.
      ls_invoice_csv-documentcurrency = 'USD'.
      APPEND ls_invoice_csv TO lt_invoice_csv.
    ENDLOOP.

    CALL FUNCTION 'SBP_CONVERT_TO_CSV_FORMAT'
      EXPORTING
        i_field_seperator    = ','
      TABLES
        i_tab_sap_data       = lt_invoice_csv
      CHANGING
        i_tab_converted_data = lt_conv_data
      EXCEPTIONS
        conversion_failed    = 1
        OTHERS               = 2.

    INSERT INITIAL LINE INTO lt_conv_data INDEX 1 ASSIGNING FIELD-SYMBOL(<fs_conv_data>).
    <fs_conv_data> = |BusinessCode,SupplierID,SupplierName,ItemID,| &&
                     |ItemDescription,DueDateOfInvoice,BusinessYear,| &&
                     |InvoiceDate,AccountingDocumentID,DocumentCreationDate,| &&
                     |Comments,Status,InvoiceAmount,DocumentCurrency|.



    LOOP AT lt_conv_data INTO DATA(ls_conv_data).
      IF sy-tabix = 1.
        lv_string = ls_conv_data.
      ELSE.
        CONCATENATE lv_string ls_conv_data INTO lv_string SEPARATED BY cl_abap_char_utilities=>newline.
      ENDIF.
    ENDLOOP.

    CALL FUNCTION 'SCMS_STRING_TO_XSTRING'
      EXPORTING
        text   = lv_string
      IMPORTING
        buffer = lv_xstring.

    get_profile_user( ).

    DATA(lo_s3_helper) = NEW zcl_aws_s3_helper( im_profile = gv_profile ).

** Try creating if not exists
    TRY.
        lo_s3_helper->create_bucket(
             im_bucket = |invoicekb-{ to_lower( sy-uname ) }|
             ).
      CATCH /aws1/cx_s3_bucketalrdyexists.
      CATCH /aws1/cx_s3_bktalrdyownedbyyou.
    ENDTRY.

    lo_s3_helper->put_object( im_bucket = |invoicekb-{ to_lower( sy-uname ) }|
                        im_key    = |{ ie_key }.csv|
                        im_data   = lv_xstring ).

  ENDMETHOD.
ENDCLASS.
