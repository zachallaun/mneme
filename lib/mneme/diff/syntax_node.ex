defmodule Mneme.Diff.SyntaxNode do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.AST
  alias Mneme.Diff.Zipper

  @hash :__hash__
  @id :__id__
  @n_descendants :__n_descendants__
  @depth :__depth__

  defstruct [
    :zipper,
    :parent,
    :id,
    :hash,
    :n_descendants,
    :form,
    :branch?,
    :binary_op?,
    :null?,
    :terminal?
  ]

  @type t :: %SyntaxNode{
          zipper: Zipper.t() | nil,
          parent: {:pop_either | {:pop_both, term()}, t()} | nil,
          id: any(),
          hash: any(),
          n_descendants: integer(),
          form: any(),
          branch?: boolean(),
          binary_op?: boolean(),
          null?: boolean(),
          terminal?: boolean()
        }

  @doc false
  def new(zipper, parent \\ nil) do
    ast = Zipper.node(zipper)
    form = form(ast)

    %SyntaxNode{
      zipper: zipper,
      parent: parent,
      id: id(zipper),
      hash: hash(ast),
      n_descendants: n_descendants(ast),
      form: form,
      branch?: Zipper.branch?(ast),
      binary_op?: binary_op?(form),
      null?: !zipper,
      terminal?: !zipper && terminal_parent?(parent)
    }
  end

  defp binary_op?(form) when is_atom(form), do: Macro.operator?(form, 2)
  defp binary_op?(_), do: false

  defp form({{:., _, _}, _, _}), do: :.
  defp form({atom, _, _}) when is_atom(atom), do: atom
  defp form({_, _}), do: :"{_,_}"
  defp form(list) when is_list(list), do: :"[]"
  defp form(literal), do: literal

  @doc false
  def terminal_parent?(nil), do: true
  def terminal_parent?({_, p}), do: p.zipper |> Zipper.skip() |> is_nil()

  @doc false
  def root!(string) when is_binary(string) do
    string |> AST.parse_string!() |> root()
  end

  @doc false
  def roots!(left, right), do: {root!(left), root!(right)}

  @doc false
  def minimized_roots!(left, right), do: minimize_nodes(root!(left), root!(right))

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
    |> with_depth()
    |> new()
  end

  defp normalize_metadata(meta) do
    for_result =
      for {k, v} <- meta do
        if Keyword.keyword?(v), do: {k, normalize_metadata(v)}, else: {k, v}
      end

    Map.new(for_result)
  end

  @doc false
  def minimize_nodes(left, right)

  def minimize_nodes(%{hash: h}, %{hash: h}), do: nil

  def minimize_nodes(%{form: :"~"} = l, %{form: :"~"} = r), do: {l, r}

  def minimize_nodes(%{form: :"{_,_}"} = l, %{form: :"{_,_}"} = r) do
    [l_k, l_v] = children(l)
    [r_k, r_v] = children(r)

    {l_children, r_children} =
      case {minimize_nodes(l_k, r_k), minimize_nodes(l_v, r_v)} do
        {nil, {l_v, r_v}} -> {[l_k, l_v], [r_k, r_v]}
        {{l_k, r_k}, nil} -> {[l_k, l_v], [r_k, r_v]}
        _ -> {[l_k, l_v], [r_k, r_v]}
      end

    {with_children(l, Enum.map(l_children, &ast/1)),
     with_children(r, Enum.map(r_children, &ast/1))}
  end

  def minimize_nodes(%{branch?: true, form: f} = l, %{branch?: true, form: f} = r) do
    case minimize_children(l, r) do
      {[], []} ->
        nil

      {[l_child], [r_child]} ->
        {l_child, r_child}

      {l_children, r_children} ->
        {with_children(l, Enum.map(l_children, &ast/1)),
         with_children(r, Enum.map(r_children, &ast/1))}
    end
  end

  def minimize_nodes(left, right), do: {left, right}

  defp minimize_children(left, right) do
    left
    |> zip_children(right)
    |> Enum.map(fn {l, r} -> minimize_nodes(l, r) end)
    |> Enum.filter(&Function.identity/1)
    |> Enum.unzip()
    |> remove_nil_children()
  end

  defp remove_nil_children({left, right}) do
    {Enum.filter(left, &Function.identity/1), Enum.filter(right, &Function.identity/1)}
  end

  defp zip_children(left, right) do
    zip_children(children(left), children(right), [])
  end

  defp zip_children([], [], acc), do: Enum.reverse(acc)

  defp zip_children([hd | rest], [], acc), do: zip_children(rest, [], [{hd, nil} | acc])
  defp zip_children([], [hd | rest], acc), do: zip_children([], rest, [{nil, hd} | acc])

  defp zip_children([hd1 | rest1], [hd2 | rest2], acc) do
    zip_children(rest1, rest2, [{hd1, hd2} | acc])
  end

  defp children(node), do: node |> next_child() |> sibling_nodes()

  defp sibling_nodes(node) do
    node
    |> Stream.unfold(fn
      %{null?: true} -> nil
      node -> {node, next_sibling(node)}
    end)
    |> Enum.to_list()
  end

  defp with_children(node, children) do
    %{node | zipper: Zipper.replace_children(node.zipper, children)}
  end

  @doc """
  Continues traversal for two potentially null nodes.
  """
  def pop(%SyntaxNode{terminal?: true} = l, %SyntaxNode{terminal?: true} = r) do
    {l, r}
  end

  def pop(left, right) do
    case {pop_all(left), pop_all(right)} do
      {%{null?: true, parent: {{:pop_both, id}, p1}},
       %{null?: true, parent: {{:pop_both, id}, p2}}} ->
        pop(next_sibling(p1), next_sibling(p2))

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
  def similar?(%SyntaxNode{null?: false, hash: h}, %SyntaxNode{null?: false, hash: h}), do: true
  def similar?(_, _), do: false

  @doc """
  Returns true if both branches have similar delimiters.
  """
  def similar_branch?(%SyntaxNode{} = left, %SyntaxNode{} = right) do
    case {left, right} do
      {%{branch?: true, form: f}, %{branch?: true, form: f}} -> true
      _ -> false
    end
  end

  @doc """
  Returns the depth of the current syntax node relative to the root.
  """
  def depth(%SyntaxNode{zipper: z}), do: get_depth(z)

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

  defp with_depth(zipper) do
    Zipper.traverse(zipper, fn z ->
      case Zipper.node(z) do
        {_, _, _} -> Zipper.update(z, &with_depth(&1, Zipper.up(z)))
        _ -> z
      end
    end)
  end

  defp with_depth({form, meta, args}, parent) do
    {form, Map.put(meta, @depth, get_depth(parent) + 1), args}
  end

  defp get_depth(z) do
    case Zipper.node(z) do
      nil -> 0
      {_, %{@depth => depth}, _} -> depth
      _ -> get_depth(Zipper.up(z))
    end
  end
end
