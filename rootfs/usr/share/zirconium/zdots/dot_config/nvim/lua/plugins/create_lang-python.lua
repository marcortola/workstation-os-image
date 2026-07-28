-- Python (PyCharm replacement): basedpyright + native ruff (LSP override set in
-- config/options.lua), neotest-python, nvim-dap-python, venv-selector — all via
-- the LazyVim extra. lang.toml covers pyproject.toml / ruff config.
return {
  { import = "lazyvim.plugins.extras.lang.python" },
  { import = "lazyvim.plugins.extras.lang.toml" },
}
