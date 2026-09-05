.pragma library

// The real /usr/share/quickshell/dms/Common/settings/SpecUtil.js, reduced to
// the one helper the spec fixture calls. It exists so the fixture can model the
// QML resource form -- `.pragma library` plus `.import "./x.js" as Alias` --
// that tooling/dms/defaults has to resolve. Without it CI exercised a plain
// JavaScript file and a parser regression against the real schema shipped
// unnoticed.
function cloneDef(def) {
    if (def === null || typeof def !== "object")
        return def;
    return JSON.parse(JSON.stringify(def));
}
