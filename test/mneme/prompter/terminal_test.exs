defmodule Mneme.Prompter.TerminalTest do
  use ExUnit.Case, async: true
  use Mneme

  alias Mneme.Prompter.Terminal

  describe "message/5" do
    setup do
      [source: mock_source(), assertion: mock_assertion()]
    end

    test "new assertion", %{source: source, assertion: assertion} do
      message = Terminal.message(source, assertion)

      auto_assert """
                  │ [Mneme] New ● example test (ExampleTest)
                  │ example_test.ex:1
                  │ 
                  │  - auto_assert :something
                  │  + auto_assert :something <- :something
                  │ 
                  │ Accept new assertion?
                  │ > 
                  │ y yes  n no  ❮ j ● k ❯\
                  """ <- message |> untag_to_string()
    end

    test "new assertion with multiple patterns", %{source: source, assertion: assertion} do
      assertion = %{assertion | patterns: assertion.patterns ++ [nil, nil]}
      message = Terminal.message(source, assertion)

      auto_assert """
                  │ [Mneme] New ● example test (ExampleTest)
                  │ example_test.ex:1
                  │ 
                  │  - auto_assert :something
                  │  + auto_assert :something <- :something
                  │ 
                  │ Accept new assertion?
                  │ > 
                  │ y yes  n no  ❮ j ●○○ k ❯\
                  """ <- message |> untag_to_string()
    end

    test "changed assertion", %{source: source, assertion: assertion} do
      assertion = %{assertion | type: :update}
      message = Terminal.message(source, assertion)

      auto_assert """
                  │ [Mneme] Changed ● example test (ExampleTest)
                  │ example_test.ex:1
                  │ 
                  │  - auto_assert :something
                  │  + auto_assert :something <- :something
                  │ 
                  │ Value has changed! Update pattern?
                  │ > 
                  │ y yes  n no  ❮ j ● k ❯\
                  """ <- message |> untag_to_string()
    end
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
      module: "ExampleTest",
      test: :"example test",
      patterns: [{nil, nil, []}]
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
