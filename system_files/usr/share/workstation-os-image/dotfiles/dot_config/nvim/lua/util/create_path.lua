-- Buffer path formatting for the yank keymaps in lua/config/keymaps.lua and the
-- Diffview panel maps in lua/plugins/git.lua.
local M = {}

local alias_by_config = {}

-- "src/" is a real directory in Python or Go: only alias it where tsconfig/jsconfig maps "@/".
local function declares_src_alias(file)
  local config =
    vim.fs.find({ "tsconfig.json", "jsconfig.json" }, { path = vim.fn.fnamemodify(file, ":p:h"), upward = true })[1]
  if not config then
    return false
  end
  if alias_by_config[config] == nil then
    alias_by_config[config] = table.concat(vim.fn.readfile(config)):find('"@/', 1, true) ~= nil
  end
  return alias_by_config[config]
end

function M.relative(file)
  local path = vim.fn.fnamemodify(file, ":.")
  if declares_src_alias(file) then
    return (path:gsub("^src/", "@/"))
  end
  return path
end

function M.absolute(file)
  return vim.fn.fnamemodify(file, ":p")
end

return M
