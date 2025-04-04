defmodule TestVideoroom.MixProject do
  use Mix.Project

  def project do
    [
      app: :test_videoroom,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {TestVideoroom.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.6.2"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_view, "~> 0.17"},
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:cowlib, "~> 2.11", override: true},
      {:membrane_rtc_engine, path: rtc_engine_path(), override: true},
      {:membrane_rtc_engine_ex_webrtc, path: Path.join(rtc_engine_path(), "../ex_webrtc/")},
      {:playwright, github: "fishjam-dev/playwright-elixir"}
    ]
  end

  defp rtc_engine_path(), do: System.get_env("RTC_ENGINE_PATH", "../../../engine/")

  defp aliases() do
    [
      "test.protobuf": [
        "use_serializer protobuf",
        "assets.deploy",
        "test --exclude containerised"
      ],
      "assets.deploy": ["cmd --cd assets yarn install", "esbuild default --minify", "phx.digest"],
      "test.containerised": ["test --only containerised"]
    ]
  end

  def cli do
    [preferred_envs: ["test.protobuf": :test]]
  end
end
