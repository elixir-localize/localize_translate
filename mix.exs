defmodule Localize.Translate.MixProject do
  use Mix.Project

  @name "Localize Translate"
  @version "1.0.0"
  @source_url "https://github.com/elixir-localize/localize_translate"

  def project do
    [
      app: :localize_translate,
      name: @name,
      source_url: @source_url,
      homepage_url: "https://hex.pm/packages/localize_translate",
      version: @version,
      elixir: "~> 1.17",
      description: "Embedded translations for Ecto schemas",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      app_list: app_list(Mix.env()),
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: [
        plt_add_apps: ~w(ecto ecto_sql inets localize mix)a,
        flags: [
          :error_handling,
          :unknown,
          :underspecs,
          :extra_return,
          :missing_return
        ]
      ]
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      formatters: ["html", "markdown"],
      extras: [
        "README.md",
        "guides/translatable_database_systems.md": [
          title: "Building Translatable Database Systems"
        ],
        "LICENSE.md": [title: "License"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_extras: [
        Guides: ~r"guides/.*"
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ecto, "~> 3.0"},
      {:localize, "~> 1.0"},

      # Optional dependencies
      {:ecto_sql, "~> 3.0", optional: true},
      {:postgrex, "~> 0.19 or ~> 1.0", optional: true},

      # Doc dependencies
      {:ex_doc, ">= 0.0.0", only: [:dev, :release], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false, optional: true}
    ] ++ maybe_json_polyfill()
  end

  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0"}]
    end
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Kip Cole"],
      links: links(),
      files: [
        "lib",
        "guides",
        "mix.exs",
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-localize/localize_translate",
      "Readme" =>
        "https://github.com/elixir-localize/localize_translate/blob/v#{@version}/README.md",
      "Changelog" =>
        "https://github.com/elixir-localize/localize_translate/blob/v#{@version}/CHANGELOG.md"
    }
  end

  # Include Ecto and Postgrex applications in tests
  def app_list(:test), do: [:ecto, :postgrex]
  def app_list(_), do: app_list()
  def app_list, do: []

  # Always compile files in "lib". In tests compile also files in
  # "test/support"
  def elixirc_paths(:test), do: elixirc_paths() ++ ["mix", "test/support"]
  def elixirc_paths(:dev), do: elixirc_paths() ++ ["mix"]
  def elixirc_paths(_), do: elixirc_paths()
  def elixirc_paths, do: ["lib"]

  defp aliases do
    [
      test: [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test"
      ]
    ]
  end
end
