pragma Singleton
import QtQuick
import Quickshell
import qs.Services as CyServices

Singleton {
    function showNotice(message, details) { CyServices.ToastService.showInfo(message || "", details || ""); }
    function showError(message, details) { CyServices.ToastService.showError(message || "", details || ""); }
    function showWarning(message, details) { CyServices.ToastService.showWarning(message || "", details || ""); }
    function showInfo(message, details) { CyServices.ToastService.showInfo(message || "", details || ""); }
}
