defmodule Mneme.Diff.SyntaxNode do
  @moduledoc false

  alias __MODULE__
  alias Mneme.Diff.AST
  alias Mneme.Diff.Zipper

  @hash :__hash__
  @id :__id__

  defstruct [:zipper, :predecessor, :id, :hash, :branch?, :null?, :terminal?]

  @type t :: %SyntaxNode{
          zipper: Zipper.zipper() | nil,
          predecessor: Zipper.zipper() | nil,
          id: any(),
          hash: any(),
          branch?: boolean(),
          null?: boolean(),
          terminal?: boolean()
        }

  @doc false
  def new(zipper, predecessor \\ nil) do
    %SyntaxNode{
      zipper: zipper,
      predecessor: predecessor,
      # id: {id(zipper), id(predecessor)},
      id: id(zipper),
      hash: zipper |> Zipper.node() |> hash(),
      branch?: zipper |> Zipper.node() |> Zipper.branch?(),
      null?: !zipper,
      terminal?: !zipper && !Zipper.skip(predecessor)
    }
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
        meta = meta |> Keyword.merge([{@hash, hash}, {@id, {i, hash}}]) |> normalize_metadata()

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

  @doc "Returns the next syntax node or the terminal node when traversal is complete."
  def next(%SyntaxNode{zipper: nil, predecessor: pred}), do: pred |> Zipper.next() |> new(pred)
  def next(%SyntaxNode{zipper: z}), do: z |> Zipper.next() |> new(z)

  @doc "Returns the first child of the current syntax node."
  def next_child(%SyntaxNode{zipper: z}), do: z |> Zipper.down() |> new(z)

  @doc "Returns the next sibling syntax node."
  def next_sibling(%SyntaxNode{zipper: z}), do: z |> Zipper.right() |> new(z)

  @doc "Skips the current branch, returning the next sibling."
  def skip(%SyntaxNode{zipper: nil, predecessor: pred}), do: pred |> Zipper.skip() |> new(pred)
  def skip(%SyntaxNode{zipper: z}), do: z |> Zipper.skip() |> new(z)

  @doc "Returns the parent syntax node."
  def parent(%SyntaxNode{zipper: z}), do: z |> Zipper.up() |> new(z)

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
  def similar?(%SyntaxNode{zipper: nil}, _), do: false
  def similar?(_, %SyntaxNode{zipper: nil}), do: false
  def similar?(%SyntaxNode{hash: hash}, %SyntaxNode{hash: hash}), do: true
  def similar?(_, _), do: false

  @doc """
  Returns the depth of the current syntax node relative to the root.
  """
  def depth(%SyntaxNode{zipper: zipper}), do: get_depth(zipper)

  defp get_depth(zipper, acc \\ 0)
  defp get_depth(nil, acc), do: acc
  defp get_depth(zipper, acc), do: get_depth(Zipper.up(zipper), acc + 1)

  @doc """
  Returns the number of descendants of the current node.
  """
  def n_descendants(%SyntaxNode{zipper: nil}), do: 0
  def n_descendants(%SyntaxNode{zipper: z}), do: get_n_descendants(z)

  defp get_n_descendants(z) do
    children = Zipper.children(z)
    length(children) + Enum.sum(Enum.map(children, &get_n_descendants/1))
  end

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
    zipper
    |> Stream.unfold(fn
      nil -> nil
      zipper -> {id(zipper), Zipper.right(zipper)}
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
end
