.pragma library

function appScopeCommand(command, enableScope) {
    const argv = Array.from(command || []);
    if (argv.length === 0 || !enableScope)
        return argv;
    if (argv[0] === "systemd-run" && argv.indexOf("--scope") >= 0)
        return argv;
    return ["systemd-run", "--user", "--scope", "--collect", "--quiet", "--slice=app.slice", "--"].concat(argv);
}
