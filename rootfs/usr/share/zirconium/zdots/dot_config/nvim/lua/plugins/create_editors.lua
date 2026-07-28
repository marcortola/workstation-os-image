-- Cross-cutting IDE parity: kulala (.http client ~ JetBrains HTTP Client),
-- aerial symbol outline/breadcrumb, and YAML/Docker language support (Symfony
-- services.yaml, compose, Containerfile/Dockerfile).
return {
  { import = "lazyvim.plugins.extras.util.rest" },
  { import = "lazyvim.plugins.extras.editor.aerial" },
  { import = "lazyvim.plugins.extras.lang.yaml" },
  { import = "lazyvim.plugins.extras.lang.docker" },
}
