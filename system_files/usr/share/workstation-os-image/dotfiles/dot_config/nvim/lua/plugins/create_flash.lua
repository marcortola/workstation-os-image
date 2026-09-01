-- "f" is remapped to "/" in lua/config/keymaps.lua, so flash must stop claiming
-- it; the rest of its char-motion keys stay.
return {
  "folke/flash.nvim",
  opts = {
    modes = {
      char = { keys = { "t", "F", "T", ";", "," } },
    },
  },
}
