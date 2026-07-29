-- Test runner core (JetBrains test-runner parity). Language extras (lang.python,
-- lang.php, ...) declare their neotest adapters as optional; test.core makes
-- them live. The vitest adapter is gated on ts scope (see lua/config/scope.lua)
-- so it only loads where a JS/TS project is in scope.
if not require("config.scope").has("ts") then
  return {}
end
return {
  -- JS/TS test runner (WebStorm test parity); lang.typescript ships no adapter.
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = { "marilari88/neotest-vitest" },
    opts = { adapters = { ["neotest-vitest"] = {} } },
  },
}
