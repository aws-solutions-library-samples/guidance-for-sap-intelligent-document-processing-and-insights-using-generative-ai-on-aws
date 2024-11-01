sap.ui.define([
	'sap/ui/core/mvc/Controller',
	'aws/fin/ap/utils/formatter'
], function (Controller,
	formatter) {
	'use strict';
	return Controller.extend("aws.fin.ap.controllers.BaseController", {

		formatter: formatter,

		setModel: function (oModel, sName) {
			return this.getView().setModel(oModel, sName);
		},
		getResourceBundle : function () {
			return this.getOwnerComponent().getModel("i18n").getResourceBundle();
		},
/**
 * 
 * @param {string} [sName="a"]
 * @returns 
 */
		getModel: function (sName) {
			return this.getView().getModel(sName);
		},
		onFlexibleColumnLayoutStateChange: function (oEvent) {
			var sLayout = oEvent.getParameter("layout"),
				iColumns = oEvent.getParameter("maxColumnsCount");

			if (iColumns === 1) {
				this.getModel("appView").setProperty("/smallScreenMode", true);
				this.getModel("appView").setProperty("/layout", "OneColumn");
			} else {
				this.getModel("appView").setProperty("/smallScreenMode", false);
				// swich back to two column mode when device orientation is changed
				if (sLayout === "OneColumn") {
					this._setLayout("Two");
				}
			}
		},
		toggleLayout: function(){
			var oDeviceModel = this.getOwnerComponent().getModel("device");
			var oAppModel = this.getModel('appView');
			if (oDeviceModel.getProperty("/system/phone")){
			    oAppModel.setProperty("/layout", "OneColumn");
			} else {
				oAppModel.setProperty("/layout", "TwoColumnsMidExpanded");
			}
		},
		_setLayout: function (sColumns) {
			if (sColumns) {
				this.getModel("appView").setProperty("/layout", sColumns + "Column" + (sColumns === "One" ? "" : "sMidExpanded"));
			}
		}
	})

});