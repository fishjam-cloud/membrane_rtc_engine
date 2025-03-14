defmodule VideoRoom.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_videoroom_demo,
      version: "0.1.0",
      elixir: "~> 1.18",
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {VideoRoom.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:phoenix, "~> 1.6"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_view, "~> 0.16.0"},
      {:phoenix_live_reload, "~> 1.2"},
      {:poison, "~> 3.1"},
      {:jason, "~> 1.2"},
      {:phoenix_inline_svg, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},

      # rtc engine dependencies
      {:membrane_rtc_engine, path: "../../engine"},
      {:membrane_rtc_engine_ex_webrtc, path: "../../ex_webrtc"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd --cd assets npm ci"],
      "assets.deploy": [
        "cmd --cd assets yarn install",
        "cmd --cd assets yarn deploy",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
