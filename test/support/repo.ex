defmodule Localize.Translate.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :localize_translate,
    adapter: Ecto.Adapters.Postgres
end
