-- ctrl+h/j/k/l moves between nvim windows and, at the edge of the layout,
-- continues into the surrounding herdr pane. herdr's own dev-flow navigate.sh
-- is the other half: it forwards these keys into the pane when nvim (or fzf) is
-- running and handles the move itself otherwise, so one chord crosses both
-- boundaries.
--
-- vim-tmux-navigator supplies the edge detection and the non-herdr path. This
-- machine runs no tmux, so its :TmuxNavigate* commands degrade to a plain
-- wincmd -- which is the correct behaviour for a bare foot window.
local WINCMD_BY_DIRECTION = { left = "h", down = "j", up = "k", right = "l" }

local function running_inside_herdr()
  return vim.env.HERDR_ENV == "1"
end

local function focus_herdr_pane(direction)
  vim.fn.system({ "herdr", "pane", "focus", "--direction", direction, "--pane", vim.env.HERDR_PANE_ID or "" })
end

local function move_within_nvim_or_leave_pane(direction)
  local origin = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. WINCMD_BY_DIRECTION[direction])
  if vim.api.nvim_get_current_win() == origin then
    focus_herdr_pane(direction)
  end
end

local function is_floating_window()
  return vim.api.nvim_win_get_config(0).relative ~= ""
end

local function navigate(tmux_cmd, tmux_dir, direction)
  return function()
    if running_inside_herdr() then
      -- A float has no meaningful window edge, so leave the pane directly.
      if is_floating_window() then
        focus_herdr_pane(direction)
        return
      end
      move_within_nvim_or_leave_pane(direction)
      return
    end
    if is_floating_window() then
      vim.fn.system("tmux select-pane " .. tmux_dir)
      return
    end
    vim.cmd(tmux_cmd)
  end
end

return {
  "christoomey/vim-tmux-navigator",
  lazy = false,
  init = function()
    vim.g.tmux_navigator_no_mappings = 1
  end,
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
  },
  keys = {
    { "<C-h>", navigate("TmuxNavigateLeft", "-L", "left"), desc = "Navigate Left" },
    { "<C-j>", navigate("TmuxNavigateDown", "-D", "down"), desc = "Navigate Down" },
    { "<C-k>", navigate("TmuxNavigateUp", "-U", "up"), desc = "Navigate Up" },
    { "<C-l>", navigate("TmuxNavigateRight", "-R", "right"), desc = "Navigate Right" },
  },
}
