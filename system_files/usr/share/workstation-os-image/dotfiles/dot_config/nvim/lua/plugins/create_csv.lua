-- CSV/TSV exports are a normal artefact of the data work here and are unreadable
-- as plain text. csvview aligns columns and pins the header; rainbow_csv colours
-- fields. The delimiter is detected from the first lines rather than assumed,
-- because semicolon exports are common outside en-US locales.
return {
  {
    "mechatroner/rainbow_csv",
    ft = { "csv", "tsv", "csv_semicolon", "csv_whitespace", "csv_pipe" },
  },
  {
    "hat0uma/csvview.nvim",
    ft = { "csv", "tsv", "csv_semicolon", "csv_whitespace", "csv_pipe" },
    cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
    opts = {
      parser = { comments = { "#", "//" } },
      view = {
        display_mode = "border",
        sticky_header = { enabled = true, separator = "─" },
      },
      keymaps = {
        textobject_field_inner = { "if", mode = { "o", "x" } },
        textobject_field_outer = { "af", mode = { "o", "x" } },
        jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
        jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
      },
    },
    config = function(_, opts)
      require("csvview").setup(opts)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "csv", "tsv", "csv_semicolon", "csv_whitespace", "csv_pipe" },
        callback = function(args)
          -- Wrapping is on globally (lua/config/options.lua); a wrapped table is
          -- unreadable, so it is off for these buffers.
          vim.wo.wrap = false
          local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 10, false)
          local counts = { [","] = 0, ["\t"] = 0, [";"] = 0, ["|"] = 0 }
          for _, line in ipairs(lines) do
            for delim in pairs(counts) do
              local _, n = line:gsub(delim, "")
              counts[delim] = counts[delim] + n
            end
          end
          local best, best_n = ",", 0
          for delim, n in pairs(counts) do
            if n > best_n then
              best, best_n = delim, n
            end
          end
          require("csvview").enable(args.buf, { parser = { delimiter = best } })
        end,
      })
    end,
  },
}
