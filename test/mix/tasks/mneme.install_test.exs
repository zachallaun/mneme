defmodule Mix.Tasks.Mneme.InstallTest do
  use ExUnit.Case
  use Mneme, default_pattern: :last

  import Igniter.Test

  test "mix mneme.install performs all setup when a project hasn't installed Mneme" do
    auto_assert """

                Update: .formatter.exs

                1 1   |# Used by "mix format"
                2 2   |[
                3   - |  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
                  3 + |  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
                  4 + |  import_deps: [:mneme]
                4 5   |]
                5 6   |


                Update: mix.exs

                     ...|
                 8  8   |      elixir: "~> 1.17",
                 9  9   |      start_permanent: Mix.env() == :prod,
                10    - |      deps: deps()
                   10 + |      deps: deps(),
                   11 + |      preferred_cli_env: ["mneme.test": :test, "mneme.watch": :test]
                11 12   |    ]
                12 13   |  end
                     ...|


                Update: test/test_helper.exs

                1 1   |ExUnit.start()
                  2 + |Mneme.start()

                """ <- test_project() |> Igniter.compose_task("mneme.install") |> diff()
  end

  describe "mix.exs" do
    test "when :preferred_cli_env already exists" do
      test_project =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  preferred_cli_env: [
                    "existing.task": :dev
                  ]
                ]
              end
            end
            """
          }
        )

      auto_assert """

                  Update: mix.exs

                       ...|
                   6  6   |      app: :test,
                   7  7   |      preferred_cli_env: [
                   8    - |        "existing.task": :dev
                      8 + |        "existing.task": :dev,
                      9 + |        "mneme.test": :test,
                     10 + |        "mneme.watch": :test
                   9 11   |      ]
                  10 12   |    ]
                       ...|

                  """ <-
                    test_project
                    |> Igniter.compose_task("mneme.install")
                    |> diff(only: "mix.exs")
    end

    test "when :preferred_cli_env already contains mneme tasks" do
      test_project =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  preferred_cli_env: [
                    "mneme.test": :test,
                    "mneme.watch": :test
                  ]
                ]
              end
            end
            """
          }
        )

      auto_assert "" <-
                    test_project
                    |> Igniter.compose_task("mneme.install")
                    |> diff(only: "mix.exs")
    end

    test "when :preferred_cli_env already contains only mneme.watch" do
      test_project =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  preferred_cli_env: [
                    "mneme.watch": :test
                  ]
                ]
              end
            end
            """
          }
        )

      auto_assert """

                  Update: mix.exs

                       ...|
                   6  6   |      app: :test,
                   7  7   |      preferred_cli_env: [
                   8    - |        "mneme.watch": :test
                      8 + |        "mneme.watch": :test,
                      9 + |        "mneme.test": :test
                   9 10   |      ]
                  10 11   |    ]
                       ...|

                  """ <-
                    test_project
                    |> Igniter.compose_task("mneme.install")
                    |> diff(only: "mix.exs")
    end

    test "when :preferred_cli_env is a call to a local function" do
      test_project =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  preferred_cli_env: preferred_cli_env()
                ]
              end

              defp preferred_cli_env do
                [
                  "existing.task": :test
                ]
              end
            end
            """
          }
        )

      auto_assert """

                  Update: mix.exs

                       ...|
                  11 11   |  defp preferred_cli_env do
                  12 12   |    [
                  13    - |      "existing.task": :test
                     13 + |      "existing.task": :test,
                     14 + |      "mneme.watch": :test
                  14 15   |    ]
                  15 16   |  end
                       ...|

                  """ <-
                    test_project
                    |> Igniter.compose_task("mneme.install")
                    |> diff(only: "mix.exs")
    end
  end

  describe "test/test_helper.exs" do
    test "when Mneme.start() is already present" do
      test_project =
        test_project(
          files: %{
            "test/test_helper.exs" => """
            ExUnit.start()
            Mneme.start()
            """
          }
        )

      auto_assert "" <-
                    test_project
                    |> Igniter.compose_task("mneme.install")
                    |> diff(only: "test/test_helper.exs")
    end

    test "when ExUnit.start/1 has options" do
      test_project =
        test_project(
          files: %{
            "test/test_helper.exs" => """
            ExUnit.start(exclude: :integration)
            """
          }
        )

      auto_assert """

                  Update: test/test_helper.exs

                  1 1   |ExUnit.start(exclude: :integration)
                    2 + |Mneme.start()

                  """ <-
                    test_project
                    |> Igniter.compose_task("mneme.install")
                    |> diff(only: "test/test_helper.exs")
    end
  end
end
