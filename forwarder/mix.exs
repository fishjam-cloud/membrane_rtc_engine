defmodule Membrane.RTC.Engine.Endpoint.Forwarder.MixProject do
  use Mix.Project

  @version "0.2.0-dev"
  @engine_github_url "https://github.com/fishjam-cloud/membrane_rtc_engine"
  @github_url "#{@engine_github_url}/tree/master/forwarder"
  @source_ref "forwarder-v#{@version}"

  def project do
    [
      app: :membrane_rtc_engine_forwarder,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "Forwarder Endpoint for Membrane RTC Engine",
      package: package(),

      # docs
      name: "Membrane RTC Engine Forwarder Endpoint",
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
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 1.2"},
      {:membrane_rtc_engine, path: "../engine"},
      {:membrane_rtc_engine_ex_webrtc, path: "../ex_webrtc"},
      {:ex_webrtc, "~> 0.12.0"},
      {:httpoison, "~> 2.0"},
      {:jason, "~> 1.2"},

      # Dev and test
      {:credo, "~> 1.6", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:excoveralls, "~> 0.16.0", only: :test, runtime: false},
      {:bypass, "~> 2.1", only: :test}
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
      source_url_pattern: "#{@engine_github_url}/blob/#{@source_ref}/ex_webrtc/%{path}#L%{line}",
      nest_modules_by_prefix: [Membrane.RTC.Engine.Endpoint]
    ]
  end
end
