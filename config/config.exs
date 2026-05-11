import Config

if File.exists?("config/#{Mix.env()}.exs") do
  import_config("#{Mix.env()}.exs")
end

config :localize_translate, ecto_repos: [Localize.Translate.Repo]

config :ecto, json_library: Localize.Translate.JSON
config :postgrex, json_library: Localize.Translate.JSON
