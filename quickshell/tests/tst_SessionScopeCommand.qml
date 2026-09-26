import QtQuick
import QtTest
import "../Common/SessionLaunch.js" as SessionLaunch

TestCase {
    name: "SessionScopeCommand"

    function test_wrapsDesktopCommandsInAppScope() {
        const scoped = SessionLaunch.appScopeCommand(["example-app", "--flag"], true);
        compare(scoped.slice(0, 7), ["systemd-run", "--user", "--scope", "--collect", "--quiet", "--slice=app.slice", "--"]);
        compare(scoped.slice(7), ["example-app", "--flag"]);
    }

    function test_doesNotDoubleWrapExistingScope() {
        const command = ["systemd-run", "--user", "--scope", "--", "example-app"];
        compare(SessionLaunch.appScopeCommand(command, true), command);
    }

    function test_fallsBackWhenScopeUnavailable() {
        const command = ["example-app"];
        compare(SessionLaunch.appScopeCommand(command, false), command);
    }
}
