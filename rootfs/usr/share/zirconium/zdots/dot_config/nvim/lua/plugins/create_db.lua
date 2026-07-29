-- Lightweight in-editor DB client (DataGrip stays for heavy work). lang.sql
-- bundles vim-dadbod + dadbod-ui + dadbod-completion. vim-dotenv lets DBUI read
-- connections from a project .env (DB_UI_<name>=url), keeping credentials out of
-- git. Native psql/mysql clients are provided by the image (Containerfile), and
-- also inside dev containers so `dev nvim` can reach the DB by compose name.
return {
  { "tpope/vim-dotenv" },
}
