defmodule Mneme.Prompter.TerminalTest do
  use ExUnit.Case
  use Mneme

  alias Mneme.Prompter.Terminal

  describe "message/5" do
    test "new assertion" do
      message = Terminal.message(mock_source(), :new, mock_context(), {0, 1}, [])

      auto_assert """
                  │ [Mneme] New ● example test (ExampleTest)
                  │ example_test.ex:1
                  │ 
                  │  - auto_assert :something
                  │  + auto_assert :something <- :something
                  │ 
                  │ Accept new assertion?
                  │ > \e7
                  │ y yes  n no  ❮ j ● k ❯\
                  """ <- message |> untag_to_string()
    end

    test "new assertion with multiple patterns" do
      message = Terminal.message(mock_source(), :new, mock_context(), {0, 3}, [])

      auto_assert """
                  │ [Mneme] New ● example test (ExampleTest)
                  │ example_test.ex:1
                  │ 
                  │  - auto_assert :something
                  │  + auto_assert :something <- :something
                  │ 
                  │ Accept new assertion?
                  │ > \e7
                  │ y yes  n no  ❮ j ●○○ k ❯\
                  """ <- message |> untag_to_string()
    end

    test "changed assertion" do
      message = Terminal.message(mock_source(), :update, mock_context(), {0, 3}, [])

      auto_assert """
                  │ [Mneme] Changed ● example test (ExampleTest)
                  │ example_test.ex:1
                  │ 
                  │  - auto_assert :something
                  │  + auto_assert :something <- :something
                  │ 
                  │ Value has changed! Update pattern?
                  │ > \e7
                  │ y yes  n no  ❮ j ●○○ k ❯\
                  """ <- message |> untag_to_string()
    end
  end

  defp untag_to_string(data) do
    data
    |> Owl.Data.untag()
    |> IO.iodata_to_binary()
  end

  defp mock_context do
    %{
      file: "example_test.ex",
      line: 1,
      module: "ExampleTest",
      test: :"example test"
    }
  end

  defp mock_source do
    Rewrite.Source.from_string("""
    auto_assert :something
    """)
    |> Rewrite.Source.update(:test,
      code: """
      auto_assert :something <- :something
      """
    )
  end
end
