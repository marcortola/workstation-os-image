-- Case conversion (camelCase/snake_case/PascalCase/...), replacing the
-- JetBrains "Toggle case style" (shift+ctrl+u). Prefix `gz` is unused by both
-- Vim and LazyVim, so it does not shadow the builtin `ga` (:ascii).
return {
  {
    "johmsalas/text-case.nvim",
    event = "VeryLazy",
    opts = {
      default_keymappings_enabled = true,
      prefix = "gz",
    },
  },
}
