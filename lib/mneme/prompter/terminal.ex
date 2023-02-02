defmodule Mneme.Prompter.Terminal do
  @moduledoc """
  Default terminal-based prompter.
  """

  @behaviour Mneme.Prompter

  @impl true
  def prompt!(patch) do
    %{
      type: type,
      context: context,
      original: original,
      replacement: replacement
    } = patch

    operation =
      case type do
        :new -> "New"
        :replace -> "Update"
      end

    message = """
    \n[Mneme] #{operation} assertion - #{context.file}:#{context.line}

    #{diff(original, replacement)}\
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
