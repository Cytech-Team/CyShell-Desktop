import QtQuick
import QtTest
import "../Common/KeybindActions.js" as Actions

TestCase {
    name: "KeybindActionsLabwc"

    function test_labwcActionsAreSelectable() {
        const categories = Actions.getCompositorCategories("labwc");
        verify(categories.includes("Window"));
        verify(categories.includes("Workspace"));
        verify(categories.includes("System"));
        compare(Actions.getActionLabel("Close", "labwc"), "Close Window");
        compare(Actions.getActionLabel("GoToDesktop right", "labwc"), "Switch Workspace");
    }

    function test_labwcArgumentRoundTripPreservesOptions() {
        const parsed = Actions.parseCompositorActionArgs("labwc", "GoToDesktop right wrap=yes");
        compare(parsed.base, "GoToDesktop");
        compare(parsed.args.value, "right wrap=yes");
        compare(Actions.buildCompositorAction("labwc", parsed.base, parsed.args), "GoToDesktop right wrap=yes");
    }

    function test_agentCliCommandsAreFirstClassDmsActions() {
        compare(Actions.getActionType("spawn dms agent open"), "dms");
        compare(Actions.getActionType("spawn dms agent review"), "dms");
        compare(Actions.getActionType("spawn dms agent stop"), "dms");
        compare(Actions.getActionLabel("spawn dms agent stop", "labwc"), "Agent: Emergency Stop");
    }
}
