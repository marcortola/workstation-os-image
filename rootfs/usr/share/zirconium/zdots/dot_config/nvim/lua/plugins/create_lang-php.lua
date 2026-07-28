-- PhpStorm replacement (PHP/Symfony). intelephense is the single LSP (selected
-- in config/options.lua; premium license read from ~/intelephense/licence.txt
-- when present). Twig via the twig extra. phpactor is added separately as an
-- RPC-only refactor engine (never a second LSP) in lang-php-refactor.lua.
return {
  { import = "lazyvim.plugins.extras.lang.php" },
  { import = "lazyvim.plugins.extras.lang.twig" },
}
