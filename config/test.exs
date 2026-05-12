import Config

config :localize_translate, Localize.Translate.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "postgres",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false

# Set the application default locale explicitly. Without this, `Localize` falls
# through to `LANG`/`LC_*` env vars which on minimal Linux CI runners can be
# `POSIX` or `C` — values that don't validate as CLDR locales.
config :localize, default_locale: :en
