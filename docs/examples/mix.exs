defmodule MnemeExamples.MixProject do
  use Mix.Project

  @app :mneme_examples

  def version, do: "0.0.0"

  def project do
    [
      app: @app,
      version: version(),
      elixir: "~> 1.14",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      deps: [
        {:mneme, path: "../../"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end
end
