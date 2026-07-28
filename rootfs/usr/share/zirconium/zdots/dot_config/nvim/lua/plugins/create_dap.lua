-- Debugging core (nvim-dap + dap-ui + mason-nvim-dap). The language extras ship
-- the per-language adapters: nvim-dap-python (debugpy), php-debug-adapter
-- (Xdebug), js-debug-adapter (node/chrome). In-container (`dev nvim`) all three
-- connect over localhost — no host<->container path mapping.
return {
  { import = "lazyvim.plugins.extras.dap.core" },
}
