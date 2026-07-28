-- Test runner core (JetBrains test-runner parity). Language extras (lang.python,
-- lang.php, ...) declare their neotest adapters as optional; test.core makes
-- them live.
return {
  { import = "lazyvim.plugins.extras.test.core" },
  -- JS/TS test runner (WebStorm test parity); lang.typescript ships no adapter.
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = { "marilari88/neotest-vitest" },
    opts = { adapters = { ["neotest-vitest"] = {} } },
  },
}
