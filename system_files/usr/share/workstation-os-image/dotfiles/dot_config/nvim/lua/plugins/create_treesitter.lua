-- The SQL extra is universal here, so its parser is worth installing eagerly.
-- jsonc is skipped: the json extra already highlights it and the parser build
-- is the slower of the two in a container.
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = { "sql" },
    ignore_install = { "jsonc" },
  },
}
