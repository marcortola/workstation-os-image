-- PhpStorm replacement (PHP/Symfony). intelephense is the single LSP (selected
-- in config/options.lua). The premium licence key is injected by `dev nvim` as
-- INTELEPHENSE_LICENCE_KEY (from the host ~/.config/intelephense/licence.key,
-- set once with `just intelephense-licence`); free tier when unset. Twig via the
-- twig extra. Gated on php scope so it never configures (and thus installs)
-- intelephense in a non-PHP container — see lua/config/scope.lua.
if not require("config.scope").has("php") then
  return {}
end
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        intelephense = {
          init_options = {
            licenceKey = vim.env.INTELEPHENSE_LICENCE_KEY, -- nil = free tier
          },
        },
      },
    },
  },
}
