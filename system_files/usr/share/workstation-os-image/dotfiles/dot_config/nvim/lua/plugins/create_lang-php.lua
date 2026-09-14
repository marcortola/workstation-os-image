-- PhpStorm replacement (PHP/Symfony). intelephense is the single LSP (selected
-- in config/options.lua). The premium licence key is injected by `dev nvim` as
-- INTELEPHENSE_LICENCE_KEY (from the host ~/.config/intelephense/licence.key,
-- set once with `just intelephense-licence`); free tier when unset. Twig via the
-- twig extra. Gated on php scope so it never configures (and thus installs)
-- intelephense in a non-PHP container -- see lua/config/scope.lua.
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
          settings = {
            intelephense = {
              files = {
                -- Symfony rebuilds var/cache constantly in dev: 24,587 files in
                -- growwer alone, every one of them a generated artefact, and
                -- intelephense walked all of them on each index (the store's
                -- lsp.log is a run of `Indexer: .../var/cache/dev/twig/….php is
                -- over the maximum file size` warnings). var/log is the same
                -- kind of noise.
                --
                -- vendor/ deliberately stays IN. It is 22,484 PHP files of
                -- framework and library symbols, which is exactly what
                -- go-to-definition needs; the handful of `over the maximum file
                -- size` warnings from there are generated data tables that
                -- intelephense already skips on its own.
                --
                -- Setting this REPLACES intelephense's default list rather than
                -- extending it, so the defaults are restated here verbatim and
                -- the two additions come last.
                exclude = {
                  "**/.git/**",
                  "**/.svn/**",
                  "**/.hg/**",
                  "**/CVS/**",
                  "**/.DS_Store/**",
                  "**/node_modules/**",
                  "**/bower_components/**",
                  "**/vendor/**/{Tests,tests}/**",
                  "**/.history/**",
                  "**/vendor/**/vendor/**",
                  "**/var/cache/**",
                  "**/var/log/**",
                },
              },
            },
          },
        },
      },
    },
  },
}
