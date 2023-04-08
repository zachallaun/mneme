defmodule Mneme.Prompter.TerminalTest do
  use ExUnit.Case, async: true
  use Mneme

  alias Mneme.Prompter.Terminal

  describe "message/3" do
    test "new assertion" do
      auto_assert """
                  [Mneme] New · example test (ExampleTest) · [diff: :text, diff_style: :stacked]
                  example_test.ex:1

                   - auto_assert :something
                   + auto_assert :something <- :something

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  
                  """ <- message(mock_assertion())

      auto_assert """
                  [Mneme] New · example test (ExampleTest) · [diff_style: :stacked]
                  example_test.ex:1

                  ──────────────────────────────────────────────────
                    -  auto_assert :something
                  ──────────────────────────────────────────────────
                    +  auto_assert :something <- :something
                  ──────────────────────────────────────────────────

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  
                  """ <- message(mock_assertion(), %{diff: :semantic})

      auto_assert """
                  [Mneme] New · example test (ExampleTest)
                  example_test.ex:1

                  ─old─────────────────────────────────────────────┬─new─────────────────────────────────────────────
                    -  auto_assert :something                      │  +  auto_assert :something <- :something        
                  ─────────────────────────────────────────────────┴─────────────────────────────────────────────────

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  
                  """ <-
                    message(mock_assertion(), %{
                      diff: :semantic,
                      diff_style: :side_by_side,
                      terminal_width: 100
                    })
    end

    test "new assertion with multiple patterns" do
      assertion = Map.update!(mock_assertion(), :patterns, &(&1 ++ [nil, nil]))

      auto_assert """
                  [Mneme] New · example test (ExampleTest) · [diff: :text, diff_style: :stacked]
                  example_test.ex:1

                   - auto_assert :something
                   + auto_assert :something <- :something

                  Accept new assertion?
                  > 
                  y yes  n no  s skip  ❮ j ●○○ k ❯
                  """ <- message(assertion)
    end

    test "changed assertion" do
      assertion = Map.put(mock_assertion(), :stage, :update)

      auto_assert """
                  [Mneme] Update · example test (ExampleTest) · [diff: :text, diff_style: :stacked]
                  example_test.ex:1

                   - auto_assert :something
                   + auto_assert :something <- :something

                  Value has changed! Update pattern?
                  > 
                  y yes  n no  s skip  
                  """ <- message(assertion)
    end
  end

  defp message(assertion, opts \\ %{diff: :text}) do
    opts =
      opts
      |> Map.put_new(:diff_style, :stacked)
      |> Map.put_new(:terminal_width, 50)

    Terminal.message(assertion, mock_diff(), opts) |> untag_to_string()
  end

  defp untag_to_string(data) do
    data
    |> Owl.Data.untag()
    |> IO.iodata_to_binary()
  end

  defp mock_assertion do
    %Mneme.Assertion{
      stage: :new,
      pattern_idx: 0,
      patterns: [{nil, nil, []}],
      context: %{
        file: "example_test.ex",
        line: 1,
        module: ExampleTest,
        test: :"example test"
      }
    }
  end

  defp mock_diff do
    left = """
    auto_assert :something\
    """

    right = """
    auto_assert :something <- :something\
    """

    %{left: left, right: right}
  end
end
