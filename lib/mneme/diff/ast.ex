# Derived from an experimental Sourceror branch:
# https://github.com/doorgan/sourceror/blob/9cdebddd3b8894772528e4411235e57cad35014c/lib/sourceror/parser.ex

defmodule Mneme.Diff.AST do
  @moduledoc false

  # Generates an AST similar to Elixir's, but enriched and normalized.
  # See "The Sourceror AST" guide from the experimental branch for more:
  # https://github.com/doorgan/sourceror/blob/9cdebddd3b8894772528e4411235e57cad35014c/guides/sourceror_ast.md
  #
  # Differences:
  # * Ignores comments

  require Sourceror

  defguard is_valid_sigil(letter) when letter in ?a..?z or letter in ?A..?Z

  @doc """
  Parse Elixir code into an enriched AST.
  """
  def parse_string!(string) do
    opts = to_quoted_opts()
    {quoted, _comments} = Sourceror.string_to_quoted!(string, opts)

    normalize_nodes(quoted)
  end

  defp to_quoted_opts do
    [
      literal_encoder: &handle_literal/2,
      static_atoms_encoder: &encode_atom/2,
      token_metadata: true,
      unescape: false,
      columns: true,
      warn_on_unnecessary_quotes: false,
      emit_warnings: false
    ]
  end

  defp encode_atom(atom, metadata) do
    {:ok, {:atom, metadata, String.to_atom(atom)}}
  end

  defp handle_literal(atom, metadata) when is_atom(atom) do
    {:ok, {:atom, metadata ++ [__literal__: true], atom}}
  end

  defp handle_literal(string, metadata) when is_binary(string) do
    {:ok, {:string, normalize_metadata(metadata), string}}
  end

  defp handle_literal({left, right}, metadata) do
    {:ok, {:{}, normalize_metadata(metadata), [left, right]}}
  end

  defp handle_literal(list, metadata) when is_list(list) do
    if metadata[:delimiter] do
      {:ok, {:charlist, metadata, List.to_string(list)}}
    else
      {:ok, {:"[]", normalize_metadata(metadata), list}}
    end
  end

  defp handle_literal(integer, metadata) when is_integer(integer) do
    {:ok, {:int, normalize_metadata(metadata), integer}}
  end

  defp handle_literal(float, metadata) when is_float(float) do
    {:ok, {:float, normalize_metadata(metadata), float}}
  end

  defp handle_literal({:atom, _, atom}, meta) do
    {:ok, {:atom, meta ++ [__literal__: true], atom}}
  end

  @doc """
  Converts regular AST nodes into Sourceror AST nodes.
  """
  def normalize_nodes(ast) do
    postwalk(ast, &normalize_node/1)
  end

  defp normalize_node({:atom, metadata, atom}) do
    if metadata[:__literal__] do
      {:atom, normalize_metadata(metadata), atom}
    else
      {:var, normalize_metadata(metadata), atom}
    end
  end

  defp normalize_node({{:var, _, var}, metadata, args}) do
    normalize_node({var, metadata, args})
  end

  defp normalize_node({name, metadata, context})
       when is_atom(name) and is_atom(context) do
    {:var, normalize_metadata(metadata), name}
  end

  defp normalize_node({{:atom, _, form}, metadata, args}) when is_list(args) do
    {form, normalize_metadata(metadata), args}
  end

  defp normalize_node({{:atom, _, form}, metadata, context}) when is_atom(context) do
    {:var, normalize_metadata(metadata), form}
  end

  defp normalize_node({:<<>>, metadata, segments}) do
    metadata = normalize_metadata(metadata)

    start_pos = Keyword.take(metadata, [:line, :column])

    if metadata[:delimiter] do
      metadata =
        if metadata[:delimiter] in ~w[""" '''] do
          Keyword.put(metadata, :indentation, metadata[:indentation])
        else
          metadata
        end

      start_pos =
        if metadata[:delimiter] in ~w[""" '''] do
          [
            line: start_pos[:line] + 1,
            column: metadata[:indentation] + 1
          ]
        else
          [
            line: start_pos[:line],
            column: start_pos[:column] + 2 + String.length(metadata[:delimiter])
          ]
        end

      {{:<<>>, :string}, metadata, normalize_interpolation(segments, start_pos)}
    else
      {:<<>>, normalize_metadata(metadata), segments}
    end
  end

  # Handles :"atoms#{with_interpolation}"
  defp normalize_node(
         {{:., _, [:erlang, :binary_to_atom]}, metadata, [{:<<>>, _, segments}, :utf8]}
       ) do
    metadata = normalize_metadata(metadata)
    start_pos = Keyword.take(metadata, [:line, :column])

    metadata =
      if metadata[:delimiter] in ~w[""" '''] do
        Keyword.put(metadata, :indentation, metadata[:indentation])
      else
        metadata
      end

    start_pos =
      if metadata[:delimiter] in ~w[""" '''] do
        [
          line: start_pos[:line] + 1,
          column: metadata[:indentation] + 1
        ]
      else
        [
          line: start_pos[:line],
          column: start_pos[:column] + 2 + String.length(metadata[:delimiter])
        ]
      end

    {{:<<>>, :atom}, metadata, normalize_interpolation(segments, start_pos)}
  end

  defp normalize_node({form, metadata, args}) when is_atom(form) do
    case {Atom.to_string(form), args} do
      {<<"sigil_", sigil>>, [args, modifiers]} when is_valid_sigil(sigil) ->
        normalize_sigil(sigil, metadata, args, modifiers)

      _ ->
        {form, normalize_metadata(metadata), args}
    end
  end

  defp normalize_node(string) when is_binary(string) do
    {:string, [], string}
  end

  defp normalize_node(quoted), do: quoted

  defp normalize_sigil(sigil, metadata, args, modifiers) do
    {:<<>>, args_meta, args} = args

    start_pos = Keyword.take(args_meta, [:line, :column])

    metadata =
      if metadata[:delimiter] in ~w[""" '''] do
        Keyword.put(metadata, :indentation, args_meta[:indentation])
      else
        metadata
      end

    start_pos =
      if metadata[:delimiter] in ~w[""" '''] do
        [
          line: start_pos[:line] + 1,
          column: args_meta[:indentation] + 1
        ]
      else
        [
          line: start_pos[:line],
          column: start_pos[:column] + 2 + String.length(metadata[:delimiter])
        ]
      end

    sigil_string = {:string, [line: metadata[:line], column: metadata[:column] + 1], <<sigil>>}

    {:"~", normalize_metadata(metadata),
     [sigil_string, normalize_interpolation(args, start_pos), modifiers]}
  end

  defp normalize_interpolation(segments, start_pos) do
    {segments, _} =
      Enum.reduce(segments, {[], start_pos}, fn
        {:string, _, string}, {segments, pos} ->
          lines = split_on_newline(string)
          length = String.length(List.last(lines) || "")

          line_count = length(lines) - 1

          column =
            if line_count > 0 do
              start_pos[:column] + length
            else
              pos[:column] + length
            end

          {[{:string, pos, string} | segments],
           [
             line: pos[:line] + line_count,
             column: column + 1
           ]}

        {:"::", _, [{_, meta, _}, {_, _, :binary}]} = segment, {segments, _pos} ->
          pos =
            meta[:closing]
            |> Keyword.take([:line, :column])
            # Add the closing }
            |> Keyword.update!(:column, &(&1 + 1))

          {[segment | segments], pos}
      end)

    Enum.reverse(segments)
  end

  defp split_on_newline(string) do
    String.split(string, ~r/\n|\r\n|\r/)
  end

  defp normalize_metadata(metadata), do: Keyword.drop(metadata, [:__literal__, :file])

  @doc """
  Depth-first traversal of ASTs with an accumulator.
  """
  def traverse(ast, acc, pre, post) when is_function(pre, 2) and is_function(post, 2) do
    {ast, acc} = pre.(ast, acc)
    do_traverse(ast, acc, pre, post)
  end

  defp do_traverse({form, meta, args}, acc, pre, post) when is_atom(form) and is_list(args) do
    {args, acc} = do_traverse_args(args, acc, pre, post)
    post.({form, meta, args}, acc)
  end

  defp do_traverse({form, meta, args}, acc, pre, post) when is_list(args) do
    {form, acc} = pre.(form, acc)
    {form, acc} = do_traverse(form, acc, pre, post)
    {args, acc} = do_traverse_args(args, acc, pre, post)
    post.({form, meta, args}, acc)
  end

  defp do_traverse({left, right}, acc, pre, post) do
    {left, acc} = pre.(left, acc)
    {left, acc} = do_traverse(left, acc, pre, post)
    {right, acc} = pre.(right, acc)
    {right, acc} = do_traverse(right, acc, pre, post)
    post.({left, right}, acc)
  end

  defp do_traverse(list, acc, pre, post) when is_list(list) do
    {list, acc} = do_traverse_args(list, acc, pre, post)
    post.(list, acc)
  end

  defp do_traverse(x, acc, _pre, post) do
    post.(x, acc)
  end

  defp do_traverse_args(args, acc, pre, post) when is_list(args) do
    :lists.mapfoldl(
      fn x, acc ->
        {x, acc} = pre.(x, acc)
        do_traverse(x, acc, pre, post)
      end,
      acc,
      args
    )
  end

  @doc """
  Performs a depth-first, pre-order traversal of quoted expressions.
  """
  def prewalk(ast, fun) when is_function(fun, 1) do
    prewalk(ast, nil, fn x, nil -> {fun.(x), nil} end)
    |> elem(0)
  end

  @doc """
  Performs a depth-first, pre-order traversal of quoted expressions
  using an accumulator.
  """
  def prewalk(ast, acc, fun) when is_function(fun, 2) do
    traverse(ast, acc, fun, fn x, a -> {x, a} end)
  end

  @doc """
  Performs a depth-first, post-order traversal of quoted expressions.
  """
  def postwalk(ast, fun) when is_function(fun, 1) do
    postwalk(ast, nil, fn x, nil -> {fun.(x), nil} end)
    |> elem(0)
  end

  @doc """
  Performs a depth-first, post-order traversal of quoted expressions
  using an accumulator.
  """
  def postwalk(ast, acc, fun) when is_function(fun, 2) do
    traverse(ast, acc, fn x, a -> {x, a} end, fun)
  end
end
