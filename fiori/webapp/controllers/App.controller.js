sap.ui.define([
    'aws/fin/ap/controllers/BaseController',
    'sap/ui/model/json/JSONModel'
], function (BaseController, JSONModel) {
    'use strict';
    return BaseController.extend("aws.fin.ap.controllers.App", {
        onInit: function () {
            var oViewModel,
            fnSetAppNotBusy,
            iOriginalBusyDelay = this.getView().getBusyIndicatorDelay();

        oViewModel = new JSONModel({
            busy : true,
            delay : 0,
            layout : "TwoColumnsMidExpanded",
            smallScreenMode : true
        });
       var oDeviceModel = this.getOwnerComponent().getModel("device");
   
       if (oDeviceModel.getProperty("/system/phone")){
        oViewModel.setProperty("/layout", "OneColumn");
       } 
        this.setModel(oViewModel, "appView");

        fnSetAppNotBusy = function() {
            oViewModel.setProperty("/busy", false);
            oViewModel.setProperty("/delay", iOriginalBusyDelay);
        };
// set the busy indicator to false when metadata load is successful
        this.getOwnerComponent().getModel().metadataLoaded().then(fnSetAppNotBusy);
        this.getOwnerComponent().getModel().attachMetadataFailed(fnSetAppNotBusy);

// set the content density class to the rootview        
        this.getView().addStyleClass(this.getOwnerComponent().getContentDensityClass());
        }
    });
});