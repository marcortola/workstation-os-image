-- Only eager-install formatters/linters that work in ANY dev container (self-
-- contained binaries, or need only the Node `dev nvim` provisions). This drops
-- the composer/PHP tools (php-cs-fixer, phpcs, twigcs, ...) that LazyVim's
-- lang.php/lang.twig extras would otherwise try to install in every container —
-- they failed with `composer: ENOENT` in Python/JS containers and starved the
-- real LSP installs. LSP servers still install on demand per filetype (via
-- mason-lspconfig); add a language-specific tool with `:MasonInstall <tool>`.
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = { "prettier", "stylua", "shfmt", "shellcheck" }
      if os.getenv("NVIM_IN_CONTAINER") then
        opts.max_concurrent_installers = 2
      end
    end,
  },
}
