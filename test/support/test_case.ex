defmodule Localize.Translate.TestCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Localize.Translate.{TestCase, Factory}
      import Ecto.Query

      alias Localize.Translate.Repo
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Localize.Translate.Repo, shared: not tags[:async])

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
