-- marksman's default root markers are `.marksman.toml` and `.git`, and $HOME
-- carries a stray `.git/` that is not a repository at all -- git itself answers
-- `fatal: not a git repository: '/var/home/marc/.git'`, it holds only an empty
-- info/ -- but `vim.fs.root` matches the NAME, not a valid repository. So any
-- markdown file opened outside a project rooted marksman at the whole home
-- directory: it then walked the podman overlay store and the Chrome profile's
-- extensions, logging ENOENT and permission errors, three separate times
-- (~/.local/state/nvim/lsp.log, most recently 2026-09-11 15:05:01).
--
-- Refusing the root rather than deleting the stub, because the stub is not ours
-- and a root at $HOME is wrong however it arises. With no root marksman still
-- serves the single file; only cross-file links and backlinks need a workspace,
-- and $HOME is not one. The comparison is on REALPATHS: $HOME is /home/marc
-- while every real path here is /var/home/marc.
--
-- markdown is a universal extra (lua/config/lazy.lua), not a scoped language,
-- so this is deliberately NOT gated on lua/config/scope.lua -- there is no
-- `markdown` key in NVIM_MASON_LANGS and gating would disable marksman
-- everywhere.
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      marksman = {
        root_dir = function(bufnr, on_dir)
          local root = vim.fs.root(bufnr, { ".marksman.toml", ".git" })
          if not root then
            return -- no root: single-file mode, which is what we want here
          end
          local uv = vim.uv or vim.loop
          local home = uv.os_homedir()
          local real_root = uv.fs_realpath(root)
          local real_home = home and uv.fs_realpath(home)
          if real_root and real_home and real_root == real_home then
            return -- $HOME is not a workspace
          end
          on_dir(root)
        end,
      },
    },
  },
}
