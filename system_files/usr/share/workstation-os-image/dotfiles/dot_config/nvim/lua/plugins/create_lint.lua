-- ESLint runs through nvim-lint rather than its language server: the LSP hits a
-- circular-reference error on flat configs, and the linter only makes sense
-- where the project actually installed it. Gated on the project's languages for
-- the same reason lua/config/lazy.lua gates the extras -- a container scoped to
-- PHP should not be told to find eslint.
local scope = require("config.scope")

local spec = {
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters = opts.linters or {}
      -- markdownlint-cli2 has no project config in most repos, so point it at
      -- ours; scratch buffers and agent notes under .claude/ get the all-off
      -- variant, where prose rules are noise rather than signal.
      opts.linters["markdownlint-cli2"] = vim.tbl_deep_extend("force", opts.linters["markdownlint-cli2"] or {}, {
        stdin = true,
        args = {
          "--config",
          function()
            local base = vim.fn.stdpath("config")
            local bufname = vim.api.nvim_buf_get_name(0)
            local is_scratch = vim.bo.buftype == "nofile" or bufname == ""
            if is_scratch or bufname:find("/.claude/", 1, true) then
              return base .. "/markdownlint-off.jsonc"
            end
            return base .. "/markdownlint.jsonc"
          end,
          "-",
        },
      })
    end,
  },
}

if scope.has("ts") then
  spec[#spec + 1] = {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        javascript = { "eslint" },
        javascriptreact = { "eslint" },
        typescript = { "eslint" },
        typescriptreact = { "eslint" },
        astro = { "eslint" },
      },
      linters = {
        eslint = {
          condition = function(ctx)
            return vim.fs.find({ "node_modules/.bin/eslint" }, { path = ctx.filename, upward = true })[1]
          end,
        },
      },
    },
  }
  spec[#spec + 1] = {
    "neovim/nvim-lspconfig",
    opts = { servers = { eslint = { enabled = false } } },
  }
end

return spec
