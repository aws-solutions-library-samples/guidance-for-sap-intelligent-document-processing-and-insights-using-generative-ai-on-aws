sap.ui.define([
    'sap/ui/core/format/NumberFormat'
], function (NumberFormat) {
    'use strict';
    return {
        formatNumber: function (vNumber) {
            var oFormat = NumberFormat.getFloatInstance({
                decimals: 2,
                groupingSize: 3,
                decimals: 2
            });
            if (vNumber) {
                var vFormattedNumber = oFormat.format(vNumber);
                return vFormattedNumber;
            }
        },
        showPDF: function (sFileName) {
            if (sFileName) {
                var extension = sFileName.split('.').pop()
                extension.toUpperCase()
                switch (extension.toUpperCase()) {
                    case "PDF":
                        return true
                        break;
                    default:
                        return false;
                        break;
                }
            }
        },
        showImage: function(sFileName) {
            if (sFileName) {
                var extension = sFileName.split('.').pop()
            
                switch (extension.toUpperCase()) {
                    case "PDF":
                        return false
                        break;
                    default:
                        return true;
                        break;
                }
            }

        },

        formatScore: function (vNumber) {

            var oFormat = NumberFormat.getFloatInstance({
                groupingSeparator: ',',
                groupingSize: 3,
                decimals: 2
            });
            if (vNumber) {
                var vFormattedNumber = oFormat.format(vNumber);
                return parseFloat(vFormattedNumber);
            }
        },

        formatRadialValueColor: function (vNumber) {
            var vPercent = parseFloat(vNumber);
            if (vPercent > 95 && vPercent < 100) {
                return 'Good'
            } else if (vPercent > 90 && vPercent < 95) {
                return 'Neutral'
            } else {
                return 'Error'
            }
        },

        formatStatusText: function (sStatus) {
            if (!sStatus) {
                return "Pending";
            }else{
                return sStatus
            }
        },
        formatStatusState: function (sStatus) {
            switch (sStatus) {
                case "Pending":
                    return "Warning"
                    break;
                case "Posted":
                    return "Success"
                    break;
                default:
                    return "Warning"
                    break;
            }

        }
    }
});