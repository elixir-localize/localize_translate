require Localize.Translate.Repo

Localize.Translate.Repo.start_link()

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Localize.Translate.Repo, :manual)
