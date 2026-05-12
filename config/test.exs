import Config

config :localize_translate, Localize.Translate.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "postgres",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false

# Prime Localize's default locale to `:en` so the lazy first-use resolution doesn't
# fall through to `LANG`/`LC_*` env vars (which on Linux CI runners can be `POSIX` or
# `C`, fail validation, and trigger recursive locale lookup while formatting the
# error message — observed as 60-second test timeouts).
config :localize, default_locale: :en
