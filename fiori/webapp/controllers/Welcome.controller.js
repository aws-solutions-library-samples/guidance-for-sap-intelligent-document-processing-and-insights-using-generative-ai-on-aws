sap.ui.define([
    'aws/fin/ap/controllers/BaseController',
    'sap/ui/core/Fragment',
    "sap/ui/core/message/Message",
    "sap/ui/model/json/JSONModel",
    "sap/ui/model/BindingMode",
    "sap/ui/core/library",
    'sap/ui/core/BusyIndicator',
    'sap/m/MessageBox',
    'sap/m/MessageToast'
], function (BaseController,
    Fragment, Message, JSONModel, BindingMode, library, BusyIndicator, MessageBox, MessageToast) {
    'use strict';
    var MessageType = library.MessageType;
    return BaseController.extend("aws.fin.ap.controllers.Welcome", {
        onInit: function () {
            this.oRouter = this.getOwnerComponent().getRouter();

            var oModel = new JSONModel({
                email: ""
            })
            
            this.setModel(oModel, "subscription")
            this.getModel("subscription").setDefaultBindingMode(BindingMode.TwoWay)
            this.messageManager = sap.ui.getCore().getMessageManager();
            this.messageManager.registerObject(this.getView(), true)
        },
        onCodeSnippetsButtonDocuPress: function (oEvent) {
            this.oRouter.navTo("code")
        },
        onSubscribeToAlertsButtonPress: function (oEvent) {
            var oButton = oEvent.getSource(),
                oView = this.getView();

            // create popover
            if (!this._pPopover) {
                this._pPopover = Fragment.load({
                    id: oView.getId(),
                    name: "aws.fin.ap.fragments.popover",
                    type: "XML",
                    controller: this
                }).then(function (oPopover) {
                    oView.addDependent(oPopover);
                    return oPopover;
                });
            }
            this._pPopover.then(function (oPopover) {
                this.getModel("subscription").setProperty("/email", "");
                oPopover.openBy(oButton);
            }.bind(this)
            );

        },
        onGettingStartedButtonPress: function(oEvent){
            var sURL = this.getResourceBundle().getText("gettingStarted");
            sap.m.URLHelper.redirect(sURL, true);
        },

        onSubscribeButtonPress: function (oEvent) {
            var oEmail = this.byId('idEmailInput');

            this.validateEmail(oEmail);
            if (!this.messageManager.getMessageModel().getData().length > 0) {
        

            this.getModel().callFunction("/SubscribetoAlerts", {
                error: function (oMsg) {
                    MessageBox.error(this.getResourceBundle().getText("msgsubscriptionerror"))
                    BusyIndicator.hide()
                },
                success: function (oMsg) {
                    BusyIndicator.hide()
                    MessageToast.show(
                        this.getResourceBundle().getText("msgsubscription"), {
                            duration: 4000
                        }
                    );
                }.bind(this),
                method: 'POST',
                urlParameters: { email: oEmail.getValue() }
              }
            );
            }
        },
        onEmailInputChange: function (oEvent) {
            var oInput = oEvent.getSource()
            this.validateEmail(oInput)
        },
        removeMessagefromTarget: function (sTarget) {
            this.messageManager.getMessageModel().getData().forEach(function (oMessage) {
                if (oMessage.target === sTarget) {
                    this.messageManager.removeMessages(oMessage)
                }
            }.bind(this)
            );
        },
        validateEmail: function (oInput) {
            var sTarget = oInput.getBindingPath("value");
            var oBinding = oInput.getBinding("value");
            var oProcessor = this.getModel("subscription");

            this.removeMessagefromTarget(sTarget);

            try {
                oBinding.getType().validateValue(oInput.getValue());

            } catch (oException) {
                this.messageManager.addMessages(new Message(
                    {
                        message: oException.message,
                        type: MessageType.Error,
                        target: sTarget,
                        processor: oProcessor
                    }
                ))
            }
        }


    });

});