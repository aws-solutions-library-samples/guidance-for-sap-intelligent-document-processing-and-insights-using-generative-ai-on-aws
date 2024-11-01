sap.ui.define([
    'aws/fin/ap/controllers/BaseController',
    'sap/ui/core/routing/History',
    'aws/fin/ap/model/models',
], function (
    BaseController, History, models
) {
    "use strict";


    return BaseController.extend("aws.fin.ap.controllers.Code", {
        
        onInit: function () {
            this.oRouter = this.getOwnerComponent().getRouter();
            this.oRouter.getRoute("code").attachMatched(this.onCodeRouteMatched, this);
            this.oEditor = this.byId("idCodeEditor");
            var sPath = this.getOwnerComponent().getModel("localresource").getProperty("/path");
    
            this.setModel(models.createCodeModel(sPath), "code");
            this.getModel("code").dataLoaded().then(function () {
                this.oEditor.setValue(this.getModel("code").getProperty("/s3"));
            }.bind(this)
            );
        },
        onCodeRouteMatched: function (oEvent) {
            this.getModel("appView").setProperty("/layout", "TwoColumnsMidExpanded");
        },
        onPageCodeNavButtonPress: function (oEvent) {
            this.oRouter.navTo("start");
        },

        onIconTabHeaderSelect: function (oEvent) {
            var oModel = this.getModel("code")
            var sFilterId = oEvent.getParameter("selectedKey");
            switch (sFilterId) {
                case "S3":
                    this.oEditor.setValue(oModel.getProperty("/s3"));
                    break;
                case "Textract":
                    this.oEditor.setValue(oModel.getProperty("/textract"));
                    break;
                    
                case "Translate":
                    this.oEditor.setValue(oModel.getProperty("/translate"));
                    break;
                case "Lambda":
                    this.oEditor.setValue(oModel.getProperty("/lambda"));
                    break;
                case "Bedrock":
                    this.oEditor.setValue(oModel.getProperty("/bedrock"));
                    break;
                default:
                    this.oEditor.setValue();
                    break;
            }
        }

    });
});