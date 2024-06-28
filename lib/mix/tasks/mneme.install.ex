defmodule Mix.Tasks.Mneme.Install do
  @moduledoc """
  Installs Mneme in a project.
  """

  use Igniter.Mix.Task

  alias Igniter.Code.Common
  alias Sourceror.Zipper, as: Z

  require Common

  def igniter(igniter, _argv) do
    igniter
    |> Igniter.Project.Formatter.import_dep(:mneme)
    |> Igniter.update_elixir_file("test/test_helper.exs", &add_mneme_start/1)
  end

  defp add_mneme_start(%Z{} = zipper) do
    case move_to_mneme_start(zipper) do
      :error ->
        zipper =
          case move_to_exunit_start(zipper) do
            {:ok, %Z{} = zipper} -> zipper
            :error -> zipper
          end

        {:ok, Common.add_code(zipper, "Mneme.start()")}

      {:ok, _} ->
        {:ok, zipper}
    end
  end

  defp move_to_exunit_start(%Z{} = zipper) do
    Common.move_to_pattern(
      zipper,
      {{:., _, [{:__aliases__, _, [:ExUnit]}, :start]}, _, _}
    )
  end

  defp move_to_mneme_start(%Z{} = zipper) do
    Common.move_to_pattern(
      zipper,
      {{:., _, [{:__aliases__, _, [:Mneme]}, :start]}, _, _}
    )
  end
end
