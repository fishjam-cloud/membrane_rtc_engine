defmodule Membrane.RTC.Engine.Endpoint.Agent.MixProject do
  use Mix.Project

  @version "0.1.0"
  @engine_github_url "https://github.com/fishjam-cloud/membrane_rtc_engine"
  @github_url "#{@engine_github_url}/tree/master/agent"
  @source_ref "agent-v#{@version}"

  def project do
    [
      app: :membrane_rtc_engine_agent,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "Agent Endpoint for Membrane RTC Engine",
      package: package(),

      # docs
      name: "Membrane RTC Engine Agent Endpoint",
      source_url: @github_url,
      homepage_url: "https://membrane.stream",
      docs: docs(),

      # test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # Engine deps
      {:membrane_rtc_engine, "~> 0.25.0"},
      {:membrane_rtc_engine_ex_webrtc, "~> 0.2.0"},

      # Regular deps
      {:membrane_core, "~> 1.2.3"},
      {:membrane_realtimer_plugin, "~> 0.10.0"},
      {:membrane_opus_plugin, "~> 0.20.0"},
      {:membrane_rtp_opus_plugin, "~> 0.10.0"},
      {:membrane_rtp_format, "~> 0.10.0"},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.20.0"},
      {:qex, "~> 0.5"},
      {:credo, "~> 1.6", only: :dev, runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:fishjam_protos, github: "fishjam-cloud/protos", sparse: "fishjam_protos"},

      # Test deps,
      {:membrane_rtc_engine_file, path: "../file", only: :test},
      {:membrane_raw_audio_parser_plugin, "~> 0.4.0"},
      {:excoveralls, "~> 0.16.0", only: :test, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membrane.stream"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      formatters: ["html"],
      source_ref: @source_ref,
      source_url_pattern: "#{@engine_github_url}/blob/#{@source_ref}/agent/%{path}#L%{line}",
      nest_modules_by_prefix: [Membrane.RTC.Engine.Endpoint]
    ]
  end
end
