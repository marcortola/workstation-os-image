-- WebStorm replacement: TypeScript/JS via vtsls (handles React/Next JSX/TSX),
-- Astro, Vue (kept for parity though there are no Vue projects today), Tailwind,
-- JSON schemas, ESLint and Prettier. Format-on-save stays off (vim.g.autoformat
-- = false); format on demand with <leader>cf.
return {
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.lang.astro" },
  { import = "lazyvim.plugins.extras.lang.vue" },
  { import = "lazyvim.plugins.extras.lang.tailwind" },
  { import = "lazyvim.plugins.extras.lang.json" },
  { import = "lazyvim.plugins.extras.linting.eslint" },
  { import = "lazyvim.plugins.extras.formatting.prettier" },
}
