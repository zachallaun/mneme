defmodule Mneme.Options do
  @moduledoc false

  @public_options [
    action: [
      type: {:in, [:prompt, :accept, :reject]},
      default: :prompt,
      doc: """
      The action to be taken when an auto-assertion updates. Actions are one of
      `:prompt`, `:accept`, or `:reject`. If `CI=true` is set in environment
      variables, the action will _always_ be `:reject`.
      """
    ],
    default_pattern: [
      type: {:in, [:infer, :first, :last]},
      default: :infer,
      doc: """
      The default pattern to be selected if prompted to update an assertion.
      Can be one of `:infer`, `:first`, or `:last`.
      """
    ],
    target: [
      type: {:in, [:mneme, :ex_unit]},
      default: :mneme,
      doc: """
      The target output for auto-assertions. If `:mneme`, the expression will
      remain an auto-assertion. If `:ex_unit`, the expression will be rewritten
      as an ExUnit assertion.
      """
    ],
    diff: [
      type: {:in, [:text, :semantic]},
      default: :text,
      doc: """
      Controls the diff engine used to display changes when an auto-assertion
      updates. Text diffs use the Myers Difference algorithm to highlight all
      changes in text, whereas semantic diffs attempt to highlight only
      meaningful changes in the value.
      """
    ]
  ]

  @private_options [
    prompter: [
      type: :atom,
      default: Mneme.Prompter.Terminal,
      doc: "Module implementing the `Mneme.Prompter` behaviour."
    ]
  ]

  @options_schema NimbleOptions.new!(@public_options ++ @private_options)

  @test_attr :mneme
  @describe_attr :mneme_describe
  @module_attr :mneme_module

  @doc """
  Register ExUnit attributes for controlling Mneme behavior.
  """
  defmacro register_attributes(opts \\ []) do
    quote do
      ExUnit.Case.register_attribute(
        __MODULE__,
        unquote(@test_attr),
        accumulate: true
      )

      ExUnit.Case.register_describe_attribute(
        __MODULE__,
        unquote(@describe_attr),
        accumulate: true
      )

      ExUnit.Case.register_module_attribute(
        __MODULE__,
        unquote(@module_attr),
        accumulate: true
      )

      Module.put_attribute(__MODULE__, unquote(@module_attr), unquote(opts))
    end
  end

  @doc """
  Returns documentation for public Mneme options.
  """
  def docs do
    NimbleOptions.docs(@public_options)
  end

  @doc """
  Fetch all valid Mneme options from the current test tags and environment.
  """
  def options(test_tags) do
    opts_from_config = Application.get_env(:mneme, :defaults, [])
    opts_from_tags = test_tags |> collect_attributes() |> Enum.map(fn {k, [v | _]} -> {k, v} end)

    opts_from_config
    |> Keyword.merge(opts_from_tags)
    |> put_opt_if(System.get_env("CI") == "true", :action, :reject)
    |> validate_opts(test_tags)
    |> Map.new()
  end

  defp put_opt_if(opts, true, k, v), do: Keyword.put(opts, k, v)
  defp put_opt_if(opts, false, _k, _v), do: opts

  defp validate_opts(opts, test_tags) do
    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, opts} ->
        opts

      {:error, %{key: key_or_keys} = error} ->
        %{file: file, line: line, module: module} = test_tags
        stacktrace_info = [file: file, line: line, module: module]

        IO.warn("[Mneme] " <> Exception.message(error), stacktrace_info)

        opts
        |> drop_opts(key_or_keys)
        |> validate_opts(test_tags)
    end
  end

  defp drop_opts(opts, key_or_keys), do: Keyword.drop(opts, List.wrap(key_or_keys))

  @doc """
  Collect all registered Mneme attributes from the given tags, in order of precedence.

  ## Examples

      iex> collect_attributes(%{})
      %{}

      iex> collect_attributes(%{registered: %{}})
      %{}

      iex> collect_attributes(%{
      ...>   registered: %{
      ...>     mneme: [[bar: 2], [bar: 1]]
      ...>   }
      ...> })
      %{bar: [2, 1]}

      iex> collect_attributes(%{
      ...>   registered: %{
      ...>      mneme_module: [[foo: 1]],
      ...>      mneme_describe: [[bar: 2], [foo: 2, bar: 1]],
      ...>      mneme: [[bar: 3, baz: 1]]
      ...>   }
      ...> })
      %{foo: [2, 1], bar: [3, 2, 1], baz: [1]}
  """
  def collect_attributes(%{registered: %{} = attrs}) do
    %{}
    |> collect_attributes(Map.get(attrs, @test_attr, []))
    |> collect_attributes(Map.get(attrs, @describe_attr, []))
    |> collect_attributes(Map.get(attrs, @module_attr, []))
  end

  def collect_attributes(_), do: %{}

  defp collect_attributes(acc, lower_priority) do
    new =
      for kw <- lower_priority,
          {k, v} <- kw,
          reduce: %{} do
        acc -> Map.update(acc, k, [v], &[v | &1])
      end
      |> Enum.map(fn {k, vs} -> {k, Enum.reverse(vs)} end)
      |> Map.new()

    Map.merge(acc, new, fn _, vs1, vs2 -> vs1 ++ vs2 end)
  end
end
