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
    frameScreenPreferences: { def: ["all"] }
};
