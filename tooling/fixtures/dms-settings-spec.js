.pragma library

    .import "./dms-spec-util.js" as Util

var SPEC = {
    barConfigs: {
        def: [{
            id: "default",
            name: "Main Bar",
            enabled: true,
            position: 0,
            screenPreferences: ["all"],
            showOnLastDisplay: true,
            leftWidgets: [],
            centerWidgets: [],
            rightWidgets: []
        }]
    },
    builtInPluginSettings: { def: {} },
    // Present so validate-overlay's home-relative check has a key to resolve
    // against. The fixture models only the keys the capture and validation
    // paths exercise, so a new assertion on a real schema key has to add it.
    customThemeFile: { def: "" },
    // Reached through the alias on purpose: it makes CI prove that
    // tooling/dms/defaults RESOLVES the .import rather than merely
    // stripping it. A strip-only parser fails here with a ReferenceError.
    frameScreenPreferences: { def: Util.cloneDef(["all"]) }
};
