defmodule Mneme.Options do
  @moduledoc false

  @config_cache {__MODULE__, :config_cache}
  @options_cache :__mneme_options_cache__

  @public_options [
    action: [
      type: {:in, [:prompt, :accept, :reject]},
      default: :prompt,
      type_doc: "`:prompt | :accept | :reject`",
      doc: """
      The action to be taken when an auto-assertion updates. If `CI=true`
      is set in environment variables, the action will _always_ be
      `:reject`.
      """
    ],
    default_pattern: [
      type: {:in, [:infer, :first, :last]},
      default: :infer,
      type_doc: "`:infer | :first | :last`",
      doc: """
      The default pattern to be selected if prompted to update an assertion.
      """
    ],
    diff: [
      type: {:in, [:text, :semantic]},
      default: :semantic,
      type_doc: "`:text | :semantic`",
      doc: """
      Controls the diff engine used to display changes when an auto-
      assertion updates. If `:semantic`, uses a custom diff engine to
      highlight only meaningful changes in the value. If `:text`, uses
      the Myers Difference algorithm to highlight all changes in text.
      """
    ],
    diff_style: [
      type: {:in, [:side_by_side, :stacked]},
      default: :side_by_side,
      type_doc: "`:side_by_side | :stacked`",
      doc: """
      Controls how diffs are rendered when the `:diff` option is set to
      `:semantic`. If `:side_by_side`, old and new code will be rendered
      side-by-side if the terminal has sufficient space. If `:stacked`,
      old and new code will be rendered one on top of the other.
      """
    ],
    force_update: [
      type: :boolean,
      default: false,
      doc: """
      Setting to `true` will force auto-assertions to update even when
      they would otherwise succeed. This can be especially helpful when
      adding new keys to maps or structs since a pattern like `%{}`
      would not normally prompt as the match still succeeds.
      """
    ],
    target: [
      type: {:in, [:mneme, :ex_unit]},
      default: :mneme,
      type_doc: "`:mneme | :ex_unit`",
      doc: """
      The target output for auto-assertions. If `:mneme`, the expression
      will remain an auto-assertion. If `:ex_unit`, the expression will
      be rewritten as an ExUnit assertion.
      """
    ]
  ]

  @private_options [
    dry_run: [
      type: :boolean,
      default: false,
      doc: "Prevents changes from being written to the file when `true`."
    ]
  ]

  @options_schema NimbleOptions.new!(@public_options ++ @private_options)

  @test_attr :mneme
  @describe_attr :mneme_describe
  @module_attr :mneme_module

  @type option :: unquote(NimbleOptions.option_typespec(@options_schema))
  @type options :: [option]

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
  Cache application-level options.
  """
  def configure(opts) do
    opts =
      opts
      |> put_opt_if(System.get_env("CI") == "true", :action, :reject)
      |> validate_opts([])

    :persistent_term.put(@config_cache, opts)

    case :ets.whereis(@options_cache) do
      :undefined -> :ok
      _ -> :ets.delete(@options_cache)
    end

    :ets.new(@options_cache, [:named_table, :public])
    :ok
  end

  @doc """
  Returns a filtered list of options that differ from their defaults.

  ## Examples

      iex> Mneme.Options.overrides(%{default_pattern: :infer, force_update: true})
      [force_update: true]

  """
  def overrides(opts) do
    sorted_opts =
      opts
      |> Keyword.new()
      |> Enum.sort_by(&elem(&1, 0))

    for {key, value} <- sorted_opts,
        attrs = @options_schema.schema[key],
        value != attrs[:default] do
      {key, value}
    end
  end

  @doc """
  Fetch all valid Mneme options from the current test tags and environment.
  """
  @spec options(test_tags :: map()) :: options
  def options(test_tags \\ %{}) do
    stacktrace_info = [file: test_tags[:file], line: test_tags[:line], module: test_tags[:module]]

    opts =
      test_tags
      |> collect_attributes()
      |> Enum.map(fn {k, [v | _]} -> {k, v} end)

    if :ets.whereis(@options_cache) == :undefined do
      validate_opts(opts, stacktrace_info)
    else
      case :ets.lookup(@options_cache, opts) do
        [{_opts, validated}] ->
          validated

        [] ->
          validated = validate_opts(opts, stacktrace_info)
          true = :ets.insert(@options_cache, {opts, validated})
          validated
      end
    end
  end

  defp put_opt_if(opts, true, k, v), do: Keyword.put(opts, k, v)
  defp put_opt_if(opts, false, _k, _v), do: opts

  defp validate_opts(opts, stacktrace_info) do
    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, opts} ->
        opts

      {:error, %{key: key_or_keys} = error} ->
        IO.warn("[Mneme] " <> Exception.message(error), stacktrace_info)

        opts
        |> drop_opts(key_or_keys)
        |> validate_opts(stacktrace_info)
    end
  end

  defp drop_opts(opts, key_or_keys), do: Keyword.drop(opts, List.wrap(key_or_keys))

  defp collect_attributes(%{registered: %{} = attrs}) do
    %{}
    |> collect_attributes(Map.get(attrs, @test_attr, []))
    |> collect_attributes(Map.get(attrs, @describe_attr, []))
    |> collect_attributes(Map.get(attrs, @module_attr, []))
    |> collect_attributes(Application.get_env(:mneme, :cli_opts, []))
    |> collect_attributes([persistent_term_get(@config_cache, [])])
  end

  defp collect_attributes(_), do: %{}

  defp collect_attributes(acc, lower_priority) do
    for_result =
      for attrs <- lower_priority,
          kv <- List.wrap(attrs),
          reduce: %{} do
        acc ->
          {k, v} =
            case kv do
              {k, v} -> {k, v}
              k when is_atom(k) -> {k, true}
            end

          v =
            if is_binary(v) do
              String.to_atom(v)
            else
              v
            end

          Map.update(acc, k, [v], &[v | &1])
      end

    new =
      Map.new(for_result, fn {k, vs} -> {k, Enum.reverse(vs)} end)

    Map.merge(acc, new, fn _, vs1, vs2 -> vs1 ++ vs2 end)
  end

  defp persistent_term_get(key, default) do
    :persistent_term.get(key)
  rescue
    ArgumentError -> default
  end
end
