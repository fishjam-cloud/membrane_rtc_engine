import Config

config :test_videoroom,
  ecto_repos: [TestVideoroom.Repo],
  # Configure serialization of media events - either JSON or protobuf
  # This variable is set during tests using the `use_serializer` task
  event_serialization: :json

# Defines the sources for typescript client
config :ts_client,
  protobuf:
    "https://github.com/fishjam-cloud/web-client-sdk.git#workspace=@fishjam-cloud/ts-client&head=main",
  json:
    "https://github.com/fishjam-cloud/web-client-sdk.git#workspace=@fishjam-cloud/ts-client&head=main"

# Configures the endpoint
config :test_videoroom, TestVideoroomWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: TestVideoroomWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: TestVideoroom.PubSub

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.12.18",
  default: [
    args:
      ~w(src/index.ts --bundle --target=es2020 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, level: :info

config :phoenix, :json_library, Jason

# The CI image is too old for the precompiled deps to work
config :bundlex, :disable_precompiled_os_deps, apps: [:ex_libsrtp]

import_config "#{config_env()}.exs"
