defmodule Mneme.Diff.SyntaxNode do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.AST
  alias Mneme.Diff.Zipper

  @hash :__hash__
  @id :__id__
  @n_descendants :__n_descendants__

  defstruct [:zipper, :parent, :id, :hash, :n_descendants, :branch?, :null?, :terminal?]

  @type t :: %SyntaxNode{
          zipper: Zipper.zipper() | nil,
          parent: {:pop_either | :pop_both, t()} | nil,
          id: any(),
          hash: any(),
          n_descendants: integer(),
          branch?: boolean(),
          null?: boolean(),
          terminal?: boolean()
        }

  @doc false
  def new(zipper, parent \\ nil) do
    ast = Zipper.node(zipper)

    %SyntaxNode{
      zipper: zipper,
      parent: parent,
      id: id(zipper),
      hash: hash(ast),
      n_descendants: n_descendants(ast),
      branch?: Zipper.branch?(ast),
      null?: !zipper,
      terminal?: !zipper && terminal_parent?(parent)
    }
  end

  @doc false
  def terminal_parent?(nil), do: true
  def terminal_parent?({_, p}), do: next_sibling(p).terminal?

  @doc false
  def root!(string) when is_binary(string) do
    string |> AST.parse_string!() |> root()
  end

  @doc """
  Creates a root syntax node from the given tree.

  This modifies the nodes of the tree, converting metadata kw lists to
  maps and adding additional id and hash metadata for quick comparisons.
  """
  def root(tree) do
    tree
    |> AST.postwalk(0, fn
      {form, meta, args} = quoted, i ->
        hash = hash(quoted)
        n_descendants = get_n_descendants(quoted)

        meta =
          meta
          |> Keyword.merge([{@hash, hash}, {@id, {i, hash}}, {@n_descendants, n_descendants}])
          |> normalize_metadata()

        {{form, meta, args}, i + 1}

      quoted, i ->
        {quoted, i}
    end)
    |> elem(0)
    |> Zipper.zip()
    |> new()
  end

  defp normalize_metadata(meta) do
    for {k, v} <- meta do
      if Keyword.keyword?(v), do: {k, normalize_metadata(v)}, else: {k, v}
    end
    |> Map.new()
  end

  @doc """
  Creates the minimized root syntax nodes for the given trees.
  """
  def minimized_roots!(left, right) do
    case minimize_nodes(root!(left), root!(right)) do
      [roots] -> roots
      [] -> nil
    end
  end

  @doc """
  Breaks down two root nodes into a list of pairs with differences.

  This is an optimization that allows tree search to perform multiple
  searches on smaller syntax nodes.
  """
  def minimize_nodes(left, right)

  def minimize_nodes(%{hash: h}, %{hash: h}), do: []

  def minimize_nodes(%{branch?: true} = l, %{branch?: true} = r) do
    if similar_branch?(l, r) do
      case minimize_children(l, r) do
        [{l_child, r_child}] -> [{l_child, r_child}]
        _ -> [{l, r}]
      end
    else
      [{l, r}]
    end
  end

  def minimize_nodes(left, right), do: [{left, right}]

  defp minimize_children(left, right) do
    zip_children(left, right)
    |> Enum.flat_map(fn {l, r} -> minimize_nodes(l, r) end)
    |> Enum.map(fn
      {nil, nil} -> {new(nil, {:pop_either, left}), new(nil, {:pop_either, right})}
      {nil, r} -> {new(nil, {:pop_either, left}), r}
      {l, nil} -> {l, new(nil, {:pop_either, right})}
      {l, r} -> {l, r}
    end)
  end

  defp zip_children(left, right) do
    zip_children(sibling_nodes(next_child(left)), sibling_nodes(next_child(right)), [])
  end

  defp zip_children([], [], acc), do: Enum.reverse(acc)

  defp zip_children([hd | rest], [], acc), do: zip_children(rest, [], [{hd, nil} | acc])
  defp zip_children([], [hd | rest], acc), do: zip_children([], rest, [{nil, hd} | acc])

  defp zip_children([hd1 | rest1], [hd2 | rest2], acc) do
    zip_children(rest1, rest2, [{hd1, hd2} | acc])
  end

  defp sibling_nodes(%SyntaxNode{} = node) do
    Stream.unfold(node, fn
      %{null?: true} -> nil
      node -> {node, next_sibling(node)}
    end)
    |> Enum.to_list()
  end

  @doc """
  Continues traversal for two potentially null nodes.
  """
  def pop(%SyntaxNode{terminal?: true} = l, %SyntaxNode{terminal?: true} = r) do
    {l, r}
  end

  def pop(left, right) do
    case {pop_all(left), pop_all(right)} do
      {%{null?: true, parent: {:pop_both, p1}} = left,
       %{null?: true, parent: {:pop_both, p2}} = right} ->
        if similar_branch?(p1, p2) do
          pop(next_sibling(p1), next_sibling(p2))
        else
          {left, right}
        end

      {left, right} ->
        {left, right}
    end
  end

  defp pop_all(%{null?: true, parent: {:pop_either, parent}}) do
    parent |> next_sibling() |> pop_all()
  end

  defp pop_all(node), do: node

  @doc "Returns the first child of the current syntax node."
  def next_child(%SyntaxNode{zipper: z} = node, entry \\ :pop_either) do
    z |> Zipper.down() |> new({entry, node})
  end

  @doc "Returns the next sibling syntax node."
  def next_sibling(%SyntaxNode{zipper: z, parent: parent}) do
    z |> Zipper.right() |> new(parent)
  end

  @doc "Returns the parent syntax node."
  def parent(%SyntaxNode{parent: {_, parent}}), do: parent
  def parent(%SyntaxNode{}), do: nil

  @doc "Returns the ast for the current node."
  def ast(%SyntaxNode{zipper: z}), do: Zipper.node(z)

  @doc """
  List the ids of all children of the current syntax node.
  """
  def child_ids(%SyntaxNode{zipper: z}), do: get_child_ids(z)

  @doc """
  Returns true if both nodes have the same content, despite location in
  the ast.
  """
  def similar?(%SyntaxNode{} = left, %SyntaxNode{} = right) do
    !left.null? && !right.null? && left.hash == right.hash
  end

  @doc """
  Returns true if both branches have similar delimiters.
  """
  def similar_branch?(%SyntaxNode{branch?: true} = left, %SyntaxNode{branch?: true} = right) do
    case {ast(left), ast(right)} do
      {{{:., _, _}, _, _}, {{:., _, _}, _, _}} -> true
      {{branch, _, _}, {branch, _, _}} -> true
      {{_, _}, {_, _}} -> true
      _ -> false
    end
  end

  def similar_branch?(_, _), do: false

  @doc """
  Returns the depth of the current syntax node relative to the root.
  """
  def depth(%SyntaxNode{zipper: zipper}), do: get_depth(zipper)

  defp get_depth(zipper, acc \\ 0)
  defp get_depth(nil, acc), do: acc
  defp get_depth(zipper, acc), do: get_depth(Zipper.up(zipper), acc + 1)

  @doc """
  Returns the number of nodes left to explore.
  """
  def n_left(%SyntaxNode{} = node), do: get_n_left(node)

  defp get_n_left(%{terminal?: true}), do: 0
  defp get_n_left(%{null?: true, parent: {_, parent}}), do: get_n_left(next_sibling(parent))
  defp get_n_left(%{branch?: true} = node), do: 1 + get_n_left(next_child(node))
  defp get_n_left(_), do: 1

  defp id(nil), do: :erlang.phash2(nil)

  defp id(zipper) do
    case Zipper.node(zipper) do
      {_, meta, _} ->
        Map.fetch!(meta, @id)

      _structural ->
        {id(Zipper.up(zipper)), position(zipper)}
    end
  end

  defp get_child_ids(zipper) do
    case Zipper.node(zipper) do
      {{_, meta, _}, _, args} when is_list(args) ->
        [Map.fetch!(meta, @id) | zipper |> Zipper.down() |> sibling_ids()]

      {_, _, args} when is_list(args) ->
        zipper |> Zipper.down() |> sibling_ids()

      {_, _} ->
        [
          zipper |> Zipper.down() |> id(),
          zipper |> Zipper.down() |> Zipper.right() |> id()
        ]

      list when is_list(list) ->
        zipper |> Zipper.down() |> sibling_ids()

      _ ->
        []
    end
  end

  defp sibling_ids(zipper) do
    zipper |> siblings() |> Enum.map(&id/1)
  end

  defp siblings(zipper) do
    zipper
    |> Stream.unfold(fn
      nil -> nil
      zipper -> {zipper, Zipper.right(zipper)}
    end)
    |> Enum.to_list()
  end

  defp position(zipper, acc \\ -1)
  defp position(nil, acc), do: acc
  defp position(zipper, acc), do: position(Zipper.left(zipper), acc + 1)

  defp hash({call, meta, args}) do
    meta[@hash] || :erlang.phash2({hash(call), hash(args)})
  end

  defp hash({left, right}) do
    :erlang.phash2({hash(left), hash(right)})
  end

  defp hash(list) when is_list(list) do
    list
    |> Enum.map(&hash/1)
    |> :erlang.phash2()
  end

  defp hash(term), do: :erlang.phash2(term)

  defp n_descendants({_, meta, _}), do: meta[@n_descendants]
  defp n_descendants({left, right}), do: 2 + n_descendants(left) + n_descendants(right)

  defp n_descendants(list) when is_list(list) do
    length(list) + (list |> Enum.map(&n_descendants/1) |> Enum.sum())
  end

  defp n_descendants(_), do: 0

  defp get_n_descendants(z) do
    children = Zipper.children(z)
    length(children) + Enum.sum(Enum.map(children, &get_n_descendants/1))
  end
end
