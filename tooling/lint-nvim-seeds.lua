-- Compile-check (loadfile: parse, do not execute) each Neovim Lua seed passed
-- as an argument. The Lua analog of `bash -n`; run from tooling/validate via the
-- image's own Neovim so the check matches Neovim's LuaJIT dialect. Exits nonzero
-- on the first syntax error, naming the file and message.
local bad = 0
for _, path in ipairs(arg) do
  local _, err = loadfile(path)
  if err then
    io.stderr:write("Lua syntax error in " .. path .. ":\n  " .. err .. "\n")
    bad = 1
  end
end
os.exit(bad)
