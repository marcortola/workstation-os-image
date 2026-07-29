-- Which languages is this Neovim session scoped to? `dev nvim` sets
-- NVIM_MASON_LANGS to the project's detected languages (see lua/config/lazy.lua,
-- which gates the LazyVim language extras on it). User plugins that configure a
-- language server or test adapter gate on this too, so they don't reintroduce a
-- language — and trigger its LSP/tool install — in a container scoped to another.
-- On the host the var is unset, so no project language is in scope (edit config
-- here; do language work via `dev nvim`).
local M = {}
local want

function M.want()
  if not want then
    want = {}
    for l in (vim.env.NVIM_MASON_LANGS or ""):gmatch("%S+") do
      want[l] = true
    end
  end
  return want
end

function M.has(lang)
  return M.want()[lang] == true
end

return M
