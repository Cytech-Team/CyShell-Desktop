import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    function getBarConfig(selector, value) {
        const selectors = ["id", "name", "index"];
        if (!selectors.includes(selector))
            return { error: "BAR_INVALID_SELECTOR" };
        const index = selector === "index" ? Number(value) : SettingsData.barConfigs.findIndex(bar => bar[selector] == value);
        const barConfig = SettingsData.barConfigs?.[index];
        return barConfig ? { barConfig } : { error: "BAR_NOT_FOUND" };
    }

    function withBarConfig(selector, value, allowIsland, action) {
        const result = getBarConfig(selector, value);
        if (result.error)
            return result.error;
        if (!allowIsland && SettingsData.isIslandBarConfig(result.barConfig))
            return "BAR_IS_ISLAND";
        return action(result.barConfig);
    }

    function dockConfigFor(selector) {
        return SettingsData.dockConfigForAction(BarWidgetService.getFocusedScreenName(), selector);
    }

    IpcHandler {
        target: "panel-state"

        function pluginState(pluginId: string, key: string): string {
            return JSON.stringify(PluginService.loadPluginState(pluginId, key, null));
        }

        function pluginStatePath(pluginId: string): string {
            return PluginService.getPluginStatePath(pluginId);
        }

        function pluginStateDebug(pluginId: string): string {
            const fv = PluginService._stateWriters?.[pluginId] || null;
            let raw = "";
            try {
                raw = fv ? String(fv.text() || "") : "";
            } catch (e) {}
            let parsed = null;
            let parseError = "";
            try {
                parsed = raw.trim() ? JSON.parse(raw) : null;
            } catch (e) {
                parseError = String(e);
            }
            return JSON.stringify({
                loaded: PluginService._stateLoaded?.[pluginId] || false,
                cache: PluginService._stateCache?.[pluginId] ?? null,
                writer: !!fv,
                path: fv ? String(fv.path || "") : "",
                rawLength: raw.length,
                rawPrefix: raw.slice(0, 80),
                parsedKeys: parsed ? Object.keys(parsed) : [],
                parseError
            });
        }
    }

    IpcHandler {
        target: "bar"

        function reveal(selector: string, value: string): string {
            return root.withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, { visible: true });
                return "BAR_SHOW_SUCCESS";
            });
        }

        function hide(selector: string, value: string): string {
            return root.withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, { visible: false });
                return "BAR_HIDE_SUCCESS";
            });
        }

        function toggle(selector: string, value: string): string {
            return root.withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, { visible: !bar.visible });
                return !bar.visible ? "BAR_SHOW_SUCCESS" : "BAR_HIDE_SUCCESS";
            });
        }

        function status(selector: string, value: string): string {
            return root.withBarConfig(selector, value, true, bar => bar.visible ? "visible" : "hidden");
        }

        function autoHide(selector: string, value: string): string {
            return root.withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, { autoHide: true });
                return "BAR_AUTO_HIDE_SUCCESS";
            });
        }

        function manualHide(selector: string, value: string): string {
            return root.withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, { autoHide: false });
                return "BAR_MANUAL_HIDE_SUCCESS";
            });
        }

        function toggleAutoHide(selector: string, value: string): string {
            return root.withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, { autoHide: !bar.autoHide });
                return bar.autoHide ? "BAR_MANUAL_HIDE_SUCCESS" : "BAR_AUTO_HIDE_SUCCESS";
            });
        }

        function toggleReveal(selector: string, value: string): string {
            return root.withBarConfig(selector, value, false, bar => {
                if (!bar.autoHide)
                    return "BAR_AUTO_HIDE_DISABLED";
                if (!(bar.visible ?? true)) {
                    SettingsData.updateBarConfig(bar.id, { visible: true });
                    SettingsData.setBarIpcReveal(bar.id, true);
                    return "BAR_REVEAL_SUCCESS";
                }
                const revealed = SettingsData.toggleBarIpcReveal(bar.id);
                return revealed ? "BAR_REVEAL_SUCCESS" : "BAR_TUCK_SUCCESS";
            });
        }

        function getPosition(selector: string, value: string): string {
            return root.withBarConfig(selector, value, true, bar => ["top", "bottom", "left", "right"][bar.position] || "unknown");
        }

        function setPosition(selector: string, value: string, position: string): string {
            return root.withBarConfig(selector, value, true, bar => {
                const map = {
                    "top": SettingsData.Position.Top,
                    "bottom": SettingsData.Position.Bottom,
                    "left": SettingsData.Position.Left,
                    "right": SettingsData.Position.Right
                };
                const pos = map[position.toLowerCase()];
                if (pos === undefined)
                    return "BAR_INVALID_POSITION";
                SettingsData.updateBarConfig(bar.id, { position: pos });
                return "BAR_POSITION_SET_SUCCESS";
            });
        }
    }

    IpcHandler {
        target: "dock"

        function reveal(): string { return revealFor(""); }
        function hide(): string { return hideFor(""); }
        function toggle(): string { return toggleFor(""); }
        function status(): string { return statusFor(""); }

        function revealFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config) return "DOCK_NOT_FOUND";
            SettingsData.updateDockConfig(config.id, { enabled: true });
            return "DOCK_SHOW_SUCCESS";
        }

        function hideFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config) return "DOCK_NOT_FOUND";
            SettingsData.updateDockConfig(config.id, { enabled: false });
            return "DOCK_HIDE_SUCCESS";
        }

        function toggleFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config) return "DOCK_NOT_FOUND";
            return config.enabled ? hideFor(config.id) : revealFor(config.id);
        }

        function statusFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            return config ? (config.enabled ? "visible" : "hidden") : "DOCK_NOT_FOUND";
        }

        function edit(): string { return editFor(""); }

        function editFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config) return "DOCK_NOT_FOUND";
            if (!config.enabled) return "DOCK_HIDDEN";
            BarWidgetService.dockEditRequested(config.id);
            return "DOCK_EDIT_SUCCESS";
        }

        function autoHide(): string { return autoHideFor("", true); }
        function manualHide(): string { return autoHideFor("", false); }

        function toggleAutoHide(): string {
            const config = root.dockConfigFor("");
            if (!config) return "DOCK_NOT_FOUND";
            return autoHideFor(config.id, !config.autoHide);
        }

        function autoHideFor(selector: string, enabled: bool): string {
            const config = root.dockConfigFor(selector);
            if (!config) return "DOCK_NOT_FOUND";
            SettingsData.updateDockConfig(config.id, { autoHide: enabled, smartAutoHide: false });
            return enabled ? "BAR_AUTO_HIDE_SUCCESS" : "BAR_MANUAL_HIDE_SUCCESS";
        }
    }

    IpcHandler {
        target: "widget"

        function toggle(widgetId: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            if (!BarWidgetService.hasWidget(widgetId)) return `WIDGET_NOT_FOUND: ${widgetId}`;
            const success = BarWidgetService.triggerWidgetPopout(widgetId);
            return success ? `WIDGET_TOGGLE_SUCCESS: ${widgetId}` : `WIDGET_TOGGLE_FAILED: ${widgetId}`;
        }

        function openWith(widgetId: string, mode: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (typeof widget.openWithMode !== "function") return `WIDGET_OPEN_WITH_NOT_SUPPORTED: ${widgetId}`;
            widget.openWithMode(mode || "all");
            return `WIDGET_OPEN_WITH_SUCCESS: ${widgetId} ${mode}`;
        }

        function toggleWith(widgetId: string, mode: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (typeof widget.toggleWithMode !== "function") return `WIDGET_TOGGLE_WITH_NOT_SUPPORTED: ${widgetId}`;
            widget.toggleWithMode(mode || "all");
            return `WIDGET_TOGGLE_WITH_SUCCESS: ${widgetId} ${mode}`;
        }

        function openQuery(widgetId: string, query: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (typeof widget.openWithQuery !== "function") return `WIDGET_OPEN_QUERY_NOT_SUPPORTED: ${widgetId}`;
            widget.openWithQuery(query || "");
            return `WIDGET_OPEN_QUERY_SUCCESS: ${widgetId}`;
        }

        function toggleQuery(widgetId: string, query: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (typeof widget.toggleWithQuery !== "function") return `WIDGET_TOGGLE_QUERY_NOT_SUPPORTED: ${widgetId}`;
            widget.toggleWithQuery(query || "");
            return `WIDGET_TOGGLE_QUERY_SUCCESS: ${widgetId}`;
        }

        function list(): string {
            const widgets = BarWidgetService.getRegisteredWidgetIds();
            if (widgets.length === 0) return "No widgets registered";
            const lines = [];
            for (const widgetId of widgets) {
                const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
                let state = "";
                if (widget?.effectiveVisible !== undefined)
                    state = widget.effectiveVisible ? " [visible]" : " [hidden]";
                lines.push(widgetId + state);
            }
            return lines.join("\n");
        }

        function status(widgetId: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (!widget.popoutTarget) return `WIDGET_NO_POPOUT: ${widgetId}`;
            return widget.popoutTarget.shouldBeVisible ? "visible" : "hidden";
        }

        function reveal(widgetId: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (typeof widget.setVisibilityOverride === "function") {
                widget.setVisibilityOverride(true);
                return `WIDGET_REVEAL_SUCCESS: ${widgetId}`;
            }
            return `WIDGET_REVEAL_NOT_SUPPORTED: ${widgetId}`;
        }

        function hide(widgetId: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (typeof widget.setVisibilityOverride === "function") {
                widget.setVisibilityOverride(false);
                return `WIDGET_HIDE_SUCCESS: ${widgetId}`;
            }
            return `WIDGET_HIDE_NOT_SUPPORTED: ${widgetId}`;
        }

        function reset(widgetId: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (typeof widget.clearVisibilityOverride === "function") {
                widget.clearVisibilityOverride();
                return `WIDGET_RESET_SUCCESS: ${widgetId}`;
            }
            return `WIDGET_RESET_NOT_SUPPORTED: ${widgetId}`;
        }

        function visibility(widgetId: string): string {
            if (!widgetId) return "ERROR: No widget ID specified";
            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget) return BarWidgetService.hasWidget(widgetId) ? `WIDGET_NOT_AVAILABLE: ${widgetId}` : `WIDGET_NOT_FOUND: ${widgetId}`;
            if (widget.effectiveVisible !== undefined)
                return widget.effectiveVisible ? "visible" : "hidden";
            return "unknown";
        }
    }
}
