defmodule Mneme.DevTest do
  @moduledoc false

  defp ex_unit_case_emitted, do: :__mneme_ex_unit_case_emitted__

  defmacro __using__(opts) do
    block = Keyword.fetch!(opts, :do)
    test = Keyword.get(opts, :test)

    quote do
      require Mneme.DevTest

      Mneme.DevTest.devtest(unquote(test), do: unquote(block))
    end
  end

  defmacro devtest(test_name \\ nil, do: block) do
    if emit?() do
      caller = __CALLER__
      test_name = test_name || :"line #{caller.line}"

      maybe_ex_unit_case =
        unless Module.get_attribute(__CALLER__.module, ex_unit_case_emitted(), false) do
          Module.put_attribute(__CALLER__.module, ex_unit_case_emitted(), true)

          quote do
            use ExUnit.Case
            use Mneme, action: :accept, default_pattern: :last

            ExUnit.configure(seed: 0)
          end
        end

      test =
        quote bind_quoted: [
                module: caller.module,
                file: caller.file,
                line: caller.line,
                test_name: test_name,
                block: Macro.escape(block)
              ] do
          test = ExUnit.Case.register_test(module, file, line, :devtest, test_name, [])

          def unquote(test)(_context) do
            import ExUnit.Assertions

            unquote(block)
          end
        end

      [maybe_ex_unit_case, test]
    end
  end

  defp emit? do
    # Application.get_env(:mneme, :devtest, false)
    true
  end
end
