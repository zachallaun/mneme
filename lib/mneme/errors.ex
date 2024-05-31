defmodule Mneme.AssertionError do
  @moduledoc false
  defexception [:message]
end

defmodule Mneme.CompileError do
  @moduledoc false
  defexception [:message]
end

defmodule Mneme.InternalError do
  @moduledoc false
  defexception [:original_error, :original_stacktrace]

  @impl true
  def message(%{original_error: e, original_stacktrace: st}) do
    """
    Mneme encountered an internal error. This is likely a bug in Mneme.

    Please consider reporting this error at https://github.com/zachallaun/mneme/issues. Thanks!

    #{Exception.format(:error, e, st)}
    """
  end
end

defmodule Mneme.UnboundVariableError do
  @moduledoc false
  defexception [:vars, :message]

  @impl true
  def message(%{message: nil} = exception) do
    %{vars: vars} = exception

    """
    Updated auto-assertion is missing at least one previously bound variable:

        #{format_vars(vars)}

    Re-run this test to ensure it still passes.
    """
  end

  def message(%{message: message}) do
    message
  end

  defp format_vars(vars) do
    vars
    |> Enum.map(fn
      {name, _context} -> name
      name -> name
    end)
    |> Enum.map_join(", ", &Atom.to_string/1)
  end
end
