sap.ui.define(["aws/fin/ap/controllers/BaseController","sap/ui/model/json/JSONModel","sap/ui/core/routing/History","sap/ui/core/BusyIndicator","sap/m/MessageToast","sap/m/MessageStrip"],function(e,t,o,n,i,r){"use strict";return e.extend("aws.fin.ap.contr+
ollers.Detail",{onInit:function(){var e,o=this.getView().getBusyIndicatorDelay();var n=new t({busy:true,delay:0});this.setModel(n,"detailView");e=function(){n.setProperty("/busy",false);n.setProperty("/delay",o)};this.getOwnerComponent().getModel().metad+
ataLoaded(true).then(e);this.getOwnerComponent().getModel().attachMetadataFailed(e);this.oRouter=this.getOwnerComponent().getRouter();this.oRouter.getRoute("detail").attachMatched(this.onRouteMatched,this)},onPageDetailNavButtonPress:function(e){const t=+
o.getInstance();const n=t.getPreviousHash();if(n!==undefined){window.history.go(-1)}else{this.oRouter.navTo("start")}},onCloseButtonPress:function(e){this.oRouter.navTo("start")},onSubmitButtonPress:function(e){var t=this.getView().getBindingContext().ge+
tPath();var o=this.getModel().getProperty(t+"/invoiceNumber");var s=e.getSource();var a=this.byId("idDetailVerticalLayout");n.show();this.getModel().callFunction("/PostDocument",{error:function(e){var t=JSON.parse(e.responseText);t.error.innererror.error+
details.forEach(function(e){var t=new r({text:e.message,showCloseButton:true,showIcon:true,type:"Error"});a.addContent(t)});n.hide()},success:function(e){i.show("Accounting Document was posted Successfully");s.setVisible(false);this.getModel().refresh();+
n.hide()}.bind(this),method:"POST",urlParameters:{InvoiceNumber:o}})},onAccountingDocumentObjectAttributePress:function(e){var t=e.getSource();var o=t.getText();sap.ushell.Container.getServiceAsync("CrossApplicationNavigation").then(function(e){e.hrefFor+
ExternalAsync({target:{semanticObject:"AccountsPayable",action:"dsiplayinvoice"},params:{DocumentNumber:o}}).then(function(e){var t=window.location.href.split("#")[0]+e;sap.m.URLHelper.redirect(t)})})},onDeleteButtonPress:function(e){var t=this.getView()+
.getBindingContext().getPath();var o=this.getModel().getProperty(t+"/invoiceNumber");var r=e.getSource();this.getModel().callFunction("/Discard",{error:function(e){n.hide()},success:function(e){i.show("Invoice was deleted Successfully");n.hide();this.oRo+
uter.navTo("start");this.getModel().refresh()}.bind(this),method:"POST",urlParameters:{InvoiceNumber:o}})},onRouteMatched:function(e){this.getModel("appView").setProperty("/layout","TwoColumnsMidExpanded");var t=e.getParameter("arguments").invoiceId;this+
.getModel().metadataLoaded().then(function(){var e=this.getModel().createKey("Invoices",{invoiceNumber:t});var o=this.getModel().createKey("InvoiceDocuments",{InvoiceNumber:t});var n=this.byId("idDocumentImage");var i=this.byId("idPDFViewer");i.setSource+
(this.getOwnerComponent().getManifestObject().getEntry("/sap.app/dataSources/appService/uri")+"/"+o+"/$value");n.setSrc(this.getOwnerComponent().getManifestObject().getEntry("/sap.app/dataSources/appService/uri")+"/"+o+"/$value");this.getView().bindEleme+
nt({path:"/"+e,parameters:{expand:"toitems"}})}.bind(this))}})});                                                                                                                                                                                              
//# sourceMappingURL=Detail.controller.js.map                                                                                                                                                                                                                  