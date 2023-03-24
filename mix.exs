defmodule Mneme.MixProject do
  use Mix.Project

  @app :mneme
  @source_url "https://github.com/zachallaun/mneme"

  def version, do: "0.2.5"

  def project do
    [
      app: @app,
      version: version(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      aliases: aliases(),
      preferred_cli_env: preferred_cli_env(),

      # Hex
      description: "Snapshot/approval testing integrated into ExUnit",
      package: package(),

      # Docs
      name: "Mneme",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:owl, "~> 0.7.0"},
      {:nimble_options, "~> 1.0"},
      {:sourceror, "~> 0.12"},
      {:rewrite, "~> 0.6.0"},
      {:libgraph, "~> 0.16.0"},

      # Development
      {:excoveralls, "~> 0.15", only: :test},
      {:ecto, "~> 3.9.4", only: :test},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:makeup_json, ">= 0.0.0", only: :dev, runtime: false},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end

  defp elixirc_paths, do: elixirc_paths(Mix.env())
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      t: "coveralls"
    ]
  end

  defp preferred_cli_env do
    [
      t: :test
    ]
  end

  defp package do
    [
      name: "mneme",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      exclude_patterns: ["priv/plts"]
    ]
  end

  defp docs do
    [
      main: "Mneme",
      api_reference: false,
      source_url: @source_url,
      extra_section: "GUIDES",
      extras: [
        "CHANGELOG.md",
        "guides/vscode_setup.md": [title: "VS Code"]
      ],
      groups_for_extras: [
        "Editor Setup": [
          "guides/vscode_setup.md"
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        :underspecs,
        :extra_return,
        :missing_return
      ]
    ]
  end
end
