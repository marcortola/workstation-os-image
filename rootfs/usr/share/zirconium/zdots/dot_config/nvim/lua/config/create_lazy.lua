-- Inside a Dev Container (launched by `dev nvim`) reuse the host's already
-- installed plugins, bind-mounted at /nvim-plugins, instead of re-cloning ~50
-- repos over the slow container network (plugins are architecture-independent;
-- Mason servers and treesitter parsers stay per-container). stdpath("config")
-- is a per-launch copy of the host config, so the lazy lock is redirected to the
-- persistent state dir and the update checker is disabled. All inert on the host.
local in_container = os.getenv("NVIM_IN_CONTAINER") ~= nil
local lazyroot = in_container and "/nvim-plugins" or (vim.fn.stdpath("data") .. "/lazy")

local lazypath = lazyroot .. "/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Language extras are scoped to the project. `dev nvim` sets NVIM_MASON_LANGS to
-- the languages it detected host-side; we import ONLY those language extras, so a
-- container gets just its language servers, treesitter parsers and mason
-- linters/formatters — not every language's. Gating the import is the single
-- scoping point: disabling only the LSP server would still leave the parser, the
-- mason tools (nvim-lint/conform then error on the missing binary), and
-- lang.astro's ts-plugin path-probe installing or warning. On the host (var
-- unset) only the universal extras load — do language work via `dev nvim`.
-- json/yaml/markdown/sql/toml are universal (loaded everywhere).
local want = require("config.scope").want()

local spec = {
  -- LazyVim core (must be first)
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
  -- Universal extras (every environment):
  { import = "lazyvim.plugins.extras.lang.json" },
  { import = "lazyvim.plugins.extras.lang.yaml" },
  { import = "lazyvim.plugins.extras.lang.markdown" },
  { import = "lazyvim.plugins.extras.lang.toml" },
  { import = "lazyvim.plugins.extras.lang.sql" },
  { import = "lazyvim.plugins.extras.formatting.prettier" },
  { import = "lazyvim.plugins.extras.test.core" },
  { import = "lazyvim.plugins.extras.dap.core" },
  { import = "lazyvim.plugins.extras.util.rest" },
  { import = "lazyvim.plugins.extras.editor.aerial" },
}
-- Project-scoped language extras (imported only when `dev nvim` detected them).
-- Left = the language key `dev.fish` emits in NVIM_MASON_LANGS; right = the
-- LazyVim extra module name (they differ for ts -> typescript).
for _, m in ipairs({
  { "python", "python" },
  { "ts", "typescript" },
  { "astro", "astro" },
  { "tailwind", "tailwind" },
  { "php", "php" },
  { "twig", "twig" },
  { "docker", "docker" },
}) do
  if want[m[1]] then
    spec[#spec + 1] = { import = "lazyvim.plugins.extras.lang." .. m[2] }
  end
end
if want.ts then
  spec[#spec + 1] = { import = "lazyvim.plugins.extras.linting.eslint" }
end
-- your own plugins (last, so they override the extras above)
spec[#spec + 1] = { import = "plugins" }

require("lazy").setup({
  root = lazyroot,
  spec = spec,
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  lockfile = in_container and (vim.fn.stdpath("state") .. "/lazy-lock.json")
    or (vim.fn.stdpath("config") .. "/lazy-lock.json"),
  -- Fewer parallel git jobs in the container: the partial-clone blob fetch
  -- flakes ("checkout failed") when many run at once over the container network.
  concurrency = in_container and 6 or nil,
  checker = {
    enabled = not in_container, -- check for plugin updates periodically (host only)
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
