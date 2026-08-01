import Config

# Connection settings come from the standard PG* environment variables so the
# same config works on CI (where the service container sets PGUSER=postgres)
# and on a developer machine (where the role is usually the login user).
config :localize_translate, Localize.Translate.Repo,
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  username: System.get_env("PGUSER", System.get_env("USER")),
  password: System.get_env("PGPASSWORD"),
  database: System.get_env("PGDATABASE", "localize_translate_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false

# Set the application default locale explicitly. Without this, `Localize` falls
# through to `LANG`/`LC_*` env vars which on minimal Linux CI runners can be
# `POSIX` or `C` — values that don't validate as CLDR locales.
config :localize, default_locale: :en
