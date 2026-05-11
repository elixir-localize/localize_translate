import Config

config :localize_translate, Localize.Translate.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "postgres",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false
