-- Case coercion (camelCase/snake_case/PascalCase/...), replacing the JetBrains
-- "Toggle case style". vim-abolish rather than text-case.nvim because IdeaVim
-- emulates abolish (`Plug 'tpope/vim-abolish'`) but has no text-case equivalent,
-- so this is the one case-conversion prefix that works identically in Neovim and
-- in PhpStorm/WebStorm.
--
-- Coercions act on the word under the cursor:
--   crs snake_case   cr_ snake_case (alias)   crc camelCase
--   crm MixedCase    crp MixedCase (alias)    cru/crU UPPER_CASE
--   cr- dash-case    crk dash-case (alias)    cr. dot.case
--   cr<Space> space case
-- crt (Title Case) exists only in IdeaVim's emulation, not in tpope's plugin, so
-- it is deliberately not listed as a shared key.
--
-- :Subvert/:S is a case-aware :substitute — :%S/facilit{y,ies}/building{,s}/g
-- rewrites facility/facilities/Facility/FACILITIES in one pass.
return {
  {
    "tpope/vim-abolish",
    event = "VeryLazy",
  },
}
