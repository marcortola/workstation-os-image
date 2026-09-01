-- Case coercion (camelCase/snake_case/PascalCase/...). vim-abolish rather than
-- text-case.nvim was originally chosen because IdeaVim emulated abolish and had
-- no text-case equivalent, so the prefix worked identically in Neovim and in the
-- JetBrains IDEs. The IDEs no longer emulate Vim -- they use their own CamelCase
-- plugin -- so that reason is gone, but abolish works and the keys are learned.
--
-- Coercions act on the word under the cursor:
--   crs snake_case   cr_ snake_case (alias)   crc camelCase
--   crm MixedCase    crp MixedCase (alias)    cru/crU UPPER_CASE
--   cr- dash-case    crk dash-case (alias)    cr. dot.case
--   cr<Space> space case
-- crt (Title Case) exists only in IdeaVim's emulation, not in tpope's plugin, so
-- it is not available here.
--
-- :Subvert/:S is a case-aware :substitute — :%S/facilit{y,ies}/building{,s}/g
-- rewrites facility/facilities/Facility/FACILITIES in one pass.
return {
  {
    "tpope/vim-abolish",
    event = "VeryLazy",
  },
}
