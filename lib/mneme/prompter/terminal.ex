defmodule Mneme.Prompter.Terminal do
  @moduledoc """
  Default terminal-based prompter.
  """

  @behaviour Mneme.Prompter

  alias Mneme.Assertion

  @impl true
  def prompt!(patch) do
    %{
      original: %{type: type, context: context} = original,
      replacement: replacement,
      format_opts: format_opts
    } = patch

    operation =
      case type do
        :new -> "New"
        :update -> "Update"
      end

    original_source = Assertion.format(original, format_opts)
    replacement_source = Assertion.format(replacement, format_opts)

    message = """
    \n[Mneme] #{operation} assertion - #{context.file}:#{context.line}

    #{diff(original_source, replacement_source)}\
    """

    IO.puts(message)

    prompt_accept?("Accept change? (y/n) ")
  end

  defp prompt_accept?(prompt, tries \\ 5)

  defp prompt_accept?(_prompt, 0), do: false

  defp prompt_accept?(prompt, tries) do
    case IO.gets(prompt) do
      response when is_binary(response) ->
        response
        |> String.trim()
        |> String.downcase()
        |> case do
          "y" ->
            true

          "n" ->
            false

          other ->
            IO.puts("unknown response: #{other}")
            prompt_accept?(prompt, tries - 1)
        end

      :eof ->
        prompt_accept?(prompt, tries - 1)
    end
  end

  defp diff(old, new) do
    Rewrite.TextDiff.format(old, new,
      line_numbers: false,
      before: 0,
      after: 0,
      format: [separator: "| "]
    )
    |> IO.iodata_to_binary()
  end
end
