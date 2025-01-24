defmodule Mneme.MixProject do
  use Mix.Project

  @app :mneme
  @source_url "https://github.com/zachallaun/mneme"

  def version, do: "0.10.2"

  def project do
    [
      app: @app,
      version: version(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls, import_cover: "cover"],
      aliases: aliases(),

      # Hex
      description: "Snapshot testing tool using familiar assertions",
      package: package(),

      # Docs
      name: "Mneme",
      docs: docs(),

      # TODO: Remove when only Elixir 1.15+ is supported
      preferred_cli_env: cli()[:preferred_envs]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :test,
        coveralls: :test,
        "coveralls.html": :test,
        "test.mneme_not_started": :test,
        "mneme.test": :test,
        "mneme.watch": :test
      ]
    ]
  end

  defp deps do
    [
      {:owl, "~> 0.9"},
      {:nimble_options, "~> 1.0"},
      {:sourceror, "~> 1.0"},
      {:rewrite, "~> 1.0"},
      {:text_diff, "~> 0.1"},
      {:file_system, "~> 1.0"},
      {:igniter, "~> 0.5.0 or ~> 0.4.0 or ~> 0.3.76"},

      # Development / Test
      {:benchee, "~> 1.0", only: :dev},
      {:ecto, "~> 3.9", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test]},
      {:time_zone_info, "~> 0.7", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:patch, "~> 0.13", only: :test},
      {:mox, "~> 1.2", only: :test},

      # Docs
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:makeup_json, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths, do: elixirc_paths(Mix.env())
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      coveralls: [
        &export_integration_coverage/1,
        "coveralls --import-cover cover"
      ],
      "coveralls.html": [
        &export_integration_coverage/1,
        "coveralls.html --import-cover cover"
      ],
      "test.mneme_not_started": [
        fn _ -> System.put_env("START_MNEME", "false") end,
        "test --only mneme_not_started test/mneme_not_started_test.exs"
      ]
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
      source_url: @source_url,
      main: "readme",
      assets: %{"docs/assets" => "assets"},
      before_closing_body_tag: fn
        :html -> ~S|<script src="assets/js/embedded-video.js"></script>|
        _ -> ""
      end,
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"],
        "docs/guides/architecture.md": [title: "Under the hood"],
        "docs/guides/vscode_setup.md": [title: "VS Code"],
        "docs/guides/generated_patterns.md": [title: "Pattern generation"]
      ],
      groups_for_extras: [
        Guides: [
          "README.md",
          "docs/guides/generated_patterns.md"
        ],
        "Editor Setup": [
          "docs/guides/vscode_setup.md"
        ],
        Internals: [
          "docs/guides/architecture.md"
        ]
      ],
      groups_for_docs: [
        Setup: &(&1[:section] == :setup),
        Assertions: &(&1[:section] == :assertion)
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        # enable warnings:
        :extra_return,
        :missing_return,
        :underspecs,

        # disable warnings:
        :no_return
      ]
    ]
  end

  defp export_integration_coverage(_) do
    Application.put_env(:mneme, :export_integration_coverage, true)
  end
end
