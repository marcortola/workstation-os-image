-- Language tools (linters/formatters/LSP servers) are scoped by which LazyVim
-- language extras get imported per project — see lua/config/lazy.lua, gated on
-- NVIM_MASON_LANGS. So a container only ever installs its own languages' tools
-- (php-cs-fixer/phpcs land in a PHP container where composer exists, never in a
-- Python one), and nvim-lint/conform never reference a tool that was dropped.
--
-- The one exception is the universal SQL extra's sqlfluff: it is a Python tool,
-- so it can't install in a container without Python (mason errors "python3
-- failed"). Drop it from the eager set unless Python is in scope; the SQL LSP
-- still provides diagnostics. Also throttle installs on the slow container net.
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      if os.getenv("NVIM_IN_CONTAINER") then
        opts.max_concurrent_installers = 2
      end
      if opts.ensure_installed and not require("config.scope").has("python") then
        opts.ensure_installed = vim.tbl_filter(function(tool)
          return tool ~= "sqlfluff"
        end, opts.ensure_installed)
      end
    end,
  },
}
