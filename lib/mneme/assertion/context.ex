defmodule Mneme.Assertion.Context do
  @moduledoc false

  import Sourceror.Identifier, only: [is_identifier: 1]

  alias Mneme.Utils

  defstruct [
    :file,
    :line,
    :module,
    :test,
    :original_pattern,
    :keysets,
    aliases: [],
    binding: [],
    map_key_pattern?: false
  ]

  @type t :: %__MODULE__{
          file: String.t(),
          line: non_neg_integer(),
          module: module(),
          test: atom(),
          original_pattern: Macro.t() | nil,
          keysets: nil | [keyset],
          aliases: list(),
          binding: Code.binding(),
          map_key_pattern?: boolean()
        }

  @type keyset :: %{
          keys: [term(), ...],
          ignore_values_for: [term()]
        }

  @doc """
  Computes and caches `context.keysets`.
  """
  @spec with_keysets(t) :: t
  def with_keysets(%__MODULE__{} = context) do
    %__MODULE__{context | keysets: get_keysets(context.original_pattern)}
  end

  # Keysets are the lists of keys being matched in any map patterns. We
  # extract them upfront so that map pattern generation can create
  # patterns for those subsets as well when applicable.
  @spec get_keysets(Macro.t(), [var]) :: [keyset] when var: {name :: atom(), context :: atom()}
  defp get_keysets(pattern, vars_to_include \\ [])

  defp get_keysets({:when, _, [pattern, guard]}, vars_to_include) do
    vars =
      guard
      |> Utils.collect_vars_from_pattern()
      |> Enum.map(fn {name, _, context} -> {name, context} end)

    get_keysets(pattern, vars ++ vars_to_include)
  end

  defp get_keysets(pattern, vars_to_include) do
    {_, keysets} =
      Macro.prewalk(pattern, [], fn
        {:%{}, _, [_ | _] = kvs} = quoted, keysets ->
          {quoted, [kvs_to_keyset(kvs, vars_to_include) | keysets]}

        quoted, keysets ->
          {quoted, keysets}
      end)

    Enum.uniq(keysets)
  end

  defp kvs_to_keyset(kvs, vars_to_include) do
    keyset =
      Enum.reduce(kvs, %{keys: [], ignore_values_for: []}, fn
        {key, {:_, _, nil}}, %{keys: keys, ignore_values_for: ignore} ->
          %{keys: [key | keys], ignore_values_for: [{key, :_} | ignore]}

        {key, {name, _, ctx} = var}, %{keys: keys, ignore_values_for: ignore}
        when is_identifier(var) ->
          if {name, ctx} in vars_to_include do
            %{keys: [key | keys], ignore_values_for: ignore}
          else
            %{keys: [key | keys], ignore_values_for: [{key, var} | ignore]}
          end

        {key, _}, keyset ->
          update_in(keyset[:keys], &[key | &1])
      end)

    update_in(keyset[:keys], &Enum.reverse/1)
  end
end
