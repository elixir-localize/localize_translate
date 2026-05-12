require Localize.Translate.Repo

# Force the default locale before any test runs. Belt-and-braces alongside the
# `config :localize, default_locale: :en` in `config/test.exs` and the
# `LOCALIZE_DEFAULT_LOCALE` env in CI — if either is somehow missing, this still
# prevents the lazy first-use lookup from falling through to a `LANG`/`LC_*` env
# value that fails validation and recurses while formatting the error message.
Localize.put_default_locale(:en)

Localize.Translate.Repo.start_link()

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Localize.Translate.Repo, :manual)
