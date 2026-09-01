-- Tab accepts, <C-j>/<C-k> move the selection, <CR> is left to insert a newline
-- rather than silently accepting whatever was highlighted. The cmdline keys
-- match, and lua/config/keymaps.lua gives the same pair to the cmdline history
-- popup so the motion is identical everywhere a list appears.
--
-- The dadbod source wires up completion we already install through the sql
-- extra (vim-dadbod-completion) but never register with blink.
return {
  "saghen/blink.cmp",
  opts = {
    keymap = {
      ["<CR>"] = {},
      ["<Tab>"] = { "accept", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
      ["<C-j>"] = { "select_next", "fallback" },
      ["<C-k>"] = { "select_prev", "fallback" },
    },
    cmdline = {
      keymap = {
        preset = "inherit",
        ["<C-j>"] = { "select_next", "fallback" },
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<Tab>"] = { "accept", "fallback" },
      },
    },
    sources = {
      per_filetype = {
        sql = { "dadbod", "snippets", "buffer" },
        mysql = { "dadbod", "snippets", "buffer" },
        plsql = { "dadbod", "snippets", "buffer" },
      },
      providers = {
        dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },
      },
    },
  },
}
