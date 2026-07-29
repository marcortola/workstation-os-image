-- basedpyright defaults to a strict type-checking mode ("recommended") that
-- floods loosely-typed code with "partially unknown" / "cannot access attribute
-- for object" warnings — far noisier than PyCharm. Dial it to "standard" so it
-- reports real errors (undefined names, bad imports) without the dynamic-typing
-- noise. Raise it back per-project with a pyrightconfig.json if you want stricter.
-- Gated on python scope so it never configures (and thus installs) basedpyright
-- in a non-Python container — see lua/config/scope.lua.
if not require("config.scope").has("python") then
  return {}
end
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "standard",
              },
            },
          },
        },
      },
    },
  },
}
