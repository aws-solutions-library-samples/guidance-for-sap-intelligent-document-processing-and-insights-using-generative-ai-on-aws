sap.ui.define([
    'aws/fin/ap/controllers/BaseController',
    'sap/ui/model/json/JSONModel',
    'sap/ui/core/routing/History',
    'sap/ui/core/BusyIndicator',
    "sap/m/MessageToast",
    'sap/m/MessageStrip',
], function (BaseController,
    JSONModel,
    History,
    BusyIndicator,
    MessageToast,
    MessageStrip,
) {
    'use strict';
    return BaseController.extend("aws.fin.ap.controllers.Detail", {
        onInit: function () {
            var fnSetAppNotBusy,
                iOriginalBusyDelay = this.getView().getBusyIndicatorDelay();

            var oViewModel = new JSONModel(
                {
                    busy: true,
                    delay: 0
                }
            );

            this.setModel(oViewModel, "detailView");

            fnSetAppNotBusy = function () {
                oViewModel.setProperty("/busy", false);
                oViewModel.setProperty("/delay", iOriginalBusyDelay);
            };

            // set the busy indicator to false when metadata load is successful
            this.getOwnerComponent().getModel().metadataLoaded(true).then(fnSetAppNotBusy);
            this.getOwnerComponent().getModel().attachMetadataFailed(fnSetAppNotBusy);

            this.oRouter = this.getOwnerComponent().getRouter();
            this.oRouter.getRoute("detail").attachMatched(this.onRouteMatched, this);
        },

        onPageDetailNavButtonPress: function (oEvent) {

            const oHistory = History.getInstance();
            const sPreviousHash = oHistory.getPreviousHash();

            if (sPreviousHash !== undefined) {
                window.history.go(-1);
            } else {
                this.oRouter.navTo("start");
            }
        },

        onCloseButtonPress: function (oEvent) {
            this.oRouter.navTo("start");
        },

        onSubmitButtonPress: function (oEvent) {

            var sPath = this.getView().getBindingContext().getPath();
            var sDocument = this.getModel().getProperty(sPath + "/invoiceNumber");
            var oButton = oEvent.getSource();
            var oVC = this.byId("idDetailVerticalLayout");
            BusyIndicator.show()
            this.getModel().callFunction("/PostDocument", {
                error: function (oMsg) {

                    var oMessageResponse = JSON.parse(oMsg.responseText);

                    oMessageResponse.error.innererror.errordetails.forEach(
                        function (oError) {

                            var oMsgStrip = new MessageStrip({
                                text: oError.message,
                                showCloseButton: true,
                                showIcon: true,
                                type: "Error"
                            });
                            oVC.addContent(oMsgStrip);
                        }
                    );

                    BusyIndicator.hide()
                },
                success: function (oMsg) {
                    MessageToast.show("Accounting Document was posted Successfully")
                    oButton.setVisible(false);
                    this.getModel().refresh();
                    BusyIndicator.hide()
                }.bind(this),
                method: 'POST',
                urlParameters: { InvoiceNumber: sDocument }
            }
            );
        },

        onAccountingDocumentObjectAttributePress: function (oEvent) {
            var oAttr = oEvent.getSource();
            var sDocument = oAttr.getText();
            sap.ushell.Container.getServiceAsync("CrossApplicationNavigation").then(function (oService) {
                oService.hrefForExternalAsync({
                    target: {
                        semanticObject: "AccountsPayable",
                        action: "dsiplayinvoice"
                    },
                    params: {
                        "DocumentNumber": sDocument
                    }
                }).then(function (sHref) {
                    // Place sHref somewhere in the DOM
                    var sURL = window.location.href.split('#')[0] + sHref;
                    sap.m.URLHelper.redirect(sURL);
                });
            });
        },

        onDeleteButtonPress: function (oEvent) {
            var sPath = this.getView().getBindingContext().getPath();
            var sDocument = this.getModel().getProperty(sPath + "/invoiceNumber");
            var oButton = oEvent.getSource();

            this.getModel().callFunction("/Discard", {
                error: function (oMsg) {

                    BusyIndicator.hide()
                },
                success: function (oMsg) {
                    MessageToast.show("Invoice was deleted Successfully")
                    BusyIndicator.hide();
                    this.oRouter.navTo('start');
                    this.getModel().refresh();
                }.bind(this),
                method: 'POST',
                urlParameters: { InvoiceNumber: sDocument }
            }
            );

        },


        onRouteMatched: function (oEvent) {
            this.getModel("appView").setProperty("/layout", "TwoColumnsMidExpanded");
            var sInvoiceId = oEvent.getParameter("arguments").invoiceId;

            this.getModel().metadataLoaded().then(function () {
                var sPath = this.getModel().createKey("Invoices", {
                    invoiceNumber: sInvoiceId
                });

                var sImagePath = this.getModel().createKey("InvoiceDocuments", {
                    InvoiceNumber: sInvoiceId
                });

                var oImg = this.byId('idDocumentImage');
                var oPDF = this.byId('idPDFViewer')

                oPDF.setSource(
                    this.getOwnerComponent().getManifestObject().getEntry("/sap.app/dataSources/appService/uri") +
                    "/" + sImagePath +
                    "/$value"
                )

                oImg.setSrc(
                    this.getOwnerComponent().getManifestObject().getEntry("/sap.app/dataSources/appService/uri") +
                    "/" + sImagePath +
                    "/$value"
                );

                this.getView().bindElement({
                    path: "/" + sPath,
                    parameters: {
                        expand: "toitems"
                    }
                });
            }.bind(this));
        }
    });

});