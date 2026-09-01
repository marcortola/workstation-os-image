-- Lightweight in-editor DB client (DataGrip stays for heavy work). lang.sql
-- bundles vim-dadbod + dadbod-ui + dadbod-completion. vim-dotenv lets DBUI read
-- connections from a project .env (DB_UI_<name>=url), keeping credentials out of
-- git. Native psql/mysql clients are provided by the image (Containerfile), and
-- also inside dev containers so `dev nvim` can reach the DB by compose name.
-- Completion is registered with blink in lua/plugins/completion.lua.
return {
  { "tpope/vim-dotenv" },
  {
    "tpope/vim-dadbod",
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_force_echo_notifications = 1
      -- Never run the buffer on save: a query buffer is edited far more often
      -- than it is meant to execute.
      vim.g.db_ui_execute_on_save = 0
      vim.g.db_ui_win_position = "left"
      vim.g.db_ui_winwidth = 40

      -- The dashboard has nothing to offer beside the DB explorer, and leaving
      -- it open makes snacks' resize handler race a half-closed window. Wipe the
      -- buffer rather than closing the window, on the next tick.
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_dbui_dashboard", { clear = true }),
        pattern = "dbui",
        callback = function()
          vim.schedule(function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(buf) then
                local ft = vim.bo[buf].filetype
                if ft == "snacks_dashboard" or ft == "dashboard" or ft == "starter" then
                  pcall(vim.api.nvim_buf_delete, buf, { force = true })
                end
              end
            end
          end)
        end,
      })
    end,
  },
}
