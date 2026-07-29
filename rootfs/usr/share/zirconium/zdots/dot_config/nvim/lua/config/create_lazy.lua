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

require("lazy").setup({
  root = lazyroot,
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
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
