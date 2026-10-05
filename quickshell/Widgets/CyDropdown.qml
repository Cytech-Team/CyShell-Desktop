import qs.CyCommon.Widgets as CyCommon
import qs.Services

CyCommon.CyDropdown {
    // Hyprland drops a focus grab when a whitelisted popup takes its own xdg grab
    popupGrabsFocus: !(CompositorService.useHyprlandFocusGrab && transientSurfaceTracker)
}
