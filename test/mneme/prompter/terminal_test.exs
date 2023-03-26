defmodule Mneme.Prompter.TerminalTest do
  use ExUnit.Case, async: true
  use Mneme

  alias Mneme.Prompter.Terminal

  describe "message/3" do
    test "new assertion" do
      auto_assert """
                  [Mneme] New ● example test (ExampleTest)
                  example_test.ex:1

                   - auto_assert :something
                   + auto_assert :something <- :something

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  \
                  """ <- message(mock_source(), mock_assertion())

      auto_assert """
                  [Mneme] New ● example test (ExampleTest)
                  example_test.ex:1

                    -  auto_assert :something

                    +  auto_assert :something <- :something

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  \
                  """ <- message(mock_source(), mock_assertion(), %{diff: :semantic})

      auto_assert """
                  [Mneme] New ● example test (ExampleTest)
                  example_test.ex:1

                  ─old──────────────────────────────────────┬─new──────────────────────────────────────
                    -  auto_assert :something               │  +  auto_assert :something <- :something 
                  ─old──────────────────────────────────────┴─new──────────────────────────────────────

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  \
                  """ <-
                    message(mock_source(), mock_assertion(), %{
                      diff: :semantic,
                      diff_style: {:side_by_side, 40}
                    })
    end

    test "new assertion with multiple patterns" do
      assertion = Map.update!(mock_assertion(), :patterns, &(&1 ++ [nil, nil]))

      auto_assert """
                  [Mneme] New ● example test (ExampleTest)
                  example_test.ex:1

                   - auto_assert :something
                   + auto_assert :something <- :something

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  ❮ j ●○○ k ❯\
                  """ <- message(mock_source(), assertion)
    end

    test "changed assertion" do
      assertion = Map.put(mock_assertion(), :type, :update)

      auto_assert """
                  [Mneme] Changed ● example test (ExampleTest)
                  example_test.ex:1

                   - auto_assert :something
                   + auto_assert :something <- :something

                  Value has changed! Update pattern?
                  > 
                  y yes  n no  s skip  \
                  """ <- message(mock_source(), assertion)
    end
  end

  defp message(source, assertion, opts \\ %{diff: :text}) do
    opts = Map.put_new(opts, :diff_style, :stacked)
    Terminal.message(source, assertion, opts) |> untag_to_string()
  end

  defp untag_to_string(data) do
    data
    |> Owl.Data.untag()
    |> IO.iodata_to_binary()
  end

  defp mock_assertion do
    %Mneme.Assertion{
      type: :new,
      file: "example_test.ex",
      line: 1,
      module: ExampleTest,
      test: :"example test",
      patterns: [{nil, nil, []}]
    }
  end

  defp mock_source do
    left = """
    auto_assert :something\
    """

    right = """
    auto_assert :something <- :something\
    """

    Rewrite.Source.from_string(left)
    |> Rewrite.Source.update(:test, code: right)
    |> Rewrite.Source.put_private(:diff, %{left: left, right: right})
  end
end
