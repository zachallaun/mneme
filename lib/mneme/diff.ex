defmodule Mneme.Diff do
  @moduledoc false

  # Structural diffing for Elixir expressions.
  #
  # This module implements structural diffing for the subset of Elixir
  # expressions that would be found in Mneme auto-assertions. It may
  # expand in the future to cover the entire Elixir language, but that
  # is currently a non-goal.
  #
  # The strategy used here draws heavily (read: is shamelessly stolen)
  # from Difftastic (https://difftastic.wilfred.me.uk/) and Autochrome
  # (https://fazzone.github.io/autochrome.html).
  #
  # It models diffing as a directed graph/tree search, where vertices
  # are cursors in the source and target ASTs and edges are diff
  # instructions, i.e. "these nodes are the same" or "the left node is
  # different". Depending on the vertex, there are many possible edges
  # with different costs. Finding similar nodes is cheaper than marking
  # one side as unique, and Dijkstra's is used to find the cheapest path
  # to the end of both ASTs.
  #
  # I've vendored and modified a handful of modules from other libraries
  # to suit them better to this task:
  #
  #   * AST - Adapted from an experimental Sourceror branch that extends
  #     quoted expressions to make them more explicit, e.g. strings
  #     become `{:string, _meta, "some string"}`.
  #
  #   * Zipper - Sourceror's Zipper implementation modified slightly to
  #     work with the extended expressions defined in AST.
  #
  #   * Pathfinding - Adapted from libgraph's pathfinding module, but
  #     refactored to create lazy implementations of A* and Dijkstra's.
  #     This allows the graph to be created lazily during pathfinding
  #     instead of having to eagerly build it up front.
  #

  alias Mneme.Diff.AST
  alias Mneme.Diff.Delta
  alias Mneme.Diff.Formatter
  alias Mneme.Diff.Pathfinding
  alias Mneme.Diff.SyntaxNode
  alias Mneme.Diff.Zipper

  @type instruction ::
          {instruction_kind, :node | :delimiter, Zipper.t()}
          | {instruction_kind, :node, Zipper.t(), edit_script}

  @type instruction_kind :: :ins | :del | :match

  @type edit_script :: [{:eq | :changed, String.t()}]

  @type vertex :: {left :: SyntaxNode.t(), right :: SyntaxNode.t(), delta :: Delta.t() | nil}

  @doc """
  Diffs and formats `left` (old) and `right` (new).
  """
  @spec format(String.t(), String.t()) :: {:ok, {Owl.Data.t(), Owl.Data.t()}} | {:error, term()}
  def format(left, right) when is_binary(left) and is_binary(right) do
    result =
      case compute_changes(left, right) do
        {[], []} -> {nil, nil}
        {[], ins} -> {nil, format_lines(right, ins)}
        {del, []} -> {format_lines(left, del), nil}
        {del, ins} -> {format_lines(left, del), format_lines(right, ins)}
      end

    {:ok, result}
  rescue
    e -> {:error, {:internal, e, __STACKTRACE__}}
  end

  @doc false
  @spec format_lines(String.t(), [instruction]) :: Owl.Data.t()
  def format_lines(code, instructions) when is_binary(code) do
    Formatter.highlight_lines(code, instructions)
  end

  @doc false
  @spec compute_changes(String.t(), String.t()) :: {[instruction], [instruction]}
  def compute_changes(left_code, right_code)
      when is_binary(left_code) and is_binary(right_code) do
    {left, right} = SyntaxNode.from_strings!(left_code, right_code)

    changes =
      {left, right, nil}
      |> shortest_path()
      |> Stream.flat_map(&List.wrap/1)
      |> Enum.filter(& &1.changed?)

    if debug?() do
      debug_inspect(summarize_path(changes), "change path")
    end

    {left_changed, right_changed} = split_sides(changes)
    {to_instructions(left_changed, :del), to_instructions(right_changed, :ins)}
  end

  @doc false
  @spec shortest_path(vertex) :: [Delta.t() | [Delta.t(), ...]]
  def shortest_path(root) do
    # The root 3-tuple doesn't have a delta, so we ignore it
    [_root | path] = Pathfinding.lazy_dijkstra(root, &vertex_id/1, &neighbors/1)
    Enum.map(path, fn {_v1, _v2, delta} -> delta end)
  end

  @doc false
  @spec split_sides([Delta.t()]) :: {[Delta.t()], [Delta.t()]}
  def split_sides(path) do
    {left, right} =
      path
      |> Stream.flat_map(&List.wrap/1)
      |> Enum.reduce({[], []}, fn
        %Delta{changed?: true, side: :left} = delta, {left, right} ->
          {[delta | left], right}

        %Delta{changed?: true, side: :right} = delta, {left, right} ->
          {left, [delta | right]}

        %Delta{changed?: false} = delta, {left, right} ->
          {[%{delta | side: :left} | left], [%{delta | side: :right} | right]}
      end)

    {Enum.reverse(left), Enum.reverse(right)}
  end

  @doc false
  @spec to_instructions(Delta.t(), instruction_kind) :: [instruction]
  def to_instructions(deltas, ins_kind) do
    Enum.map(deltas, fn
      %{changed?: false, kind: :branch} = delta ->
        {:match, :delimiter, Delta.node(delta).zipper}

      %{changed?: false, kind: :node} = delta ->
        {:match, :node, Delta.node(delta).zipper}

      %{changed?: true, edit_script: edit_script} = delta when edit_script != [] ->
        {ins_kind, :node, Delta.node(delta).zipper, edit_script}

      %{changed?: true, kind: :node} = delta ->
        {ins_kind, :node, Delta.node(delta).zipper}

      %{changed?: true, kind: :branch} = delta ->
        {ins_kind, :delimiter, Delta.node(delta).zipper}
    end)
  end

  defp neighbors({l, r, e} = v) do
    if debug?("verbose") do
      debug_inspect(summarize_delta(e), "e")
      debug_inspect(summarize_node(l), "l")
      debug_inspect(summarize_node(r), "r")
      IO.puts("")
    end

    get_neighbors(v)
  end

  defp get_neighbors({%{terminal?: true}, %{terminal?: true}, _}), do: :halt

  defp get_neighbors({left, right, _} = v) do
    if SyntaxNode.similar?(left, right) do
      {:cont, add_unchanged_node([], v)}
    else
      {:cont,
       []
       |> maybe_add_unchanged_branch(v)
       |> add_changed_edges(v)}
    end
  end

  defp add_unchanged_node(neighbors, {left, right, prev} = v) do
    delta =
      Delta.unchanged(
        :node,
        left,
        right,
        abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)),
        prev
      )

    add_edge(neighbors, v, {SyntaxNode.next_sibling(left), SyntaxNode.next_sibling(right), delta})
  end

  defp maybe_add_unchanged_branch(
         neighbors,
         {%{branch?: true} = left, %{branch?: true} = right, prev} = v
       ) do
    if SyntaxNode.similar_branch?(left, right) do
      delta =
        Delta.unchanged(
          :branch,
          left,
          right,
          abs(SyntaxNode.depth(left) - SyntaxNode.depth(right)),
          prev
        )

      v2 =
        {SyntaxNode.next_child(left, :pop_both), SyntaxNode.next_child(right, :pop_both), delta}

      add_edge(neighbors, v, v2)
    else
      neighbors
    end
  end

  defp maybe_add_unchanged_branch(neighbors, _v), do: neighbors

  # When both nodes are strings, we may want to include a Myers edit script
  defp add_changed_edges(neighbors, {%{form: :string} = left, %{form: :string} = right, _} = v) do
    case {SyntaxNode.ast(left), SyntaxNode.ast(right)} do
      {{:string, _, s1}, {:string, _, s2}} when is_binary(s1) and is_binary(s2) ->
        if String.bag_distance(s1, s2) > 0.5 do
          {left_edit, right_edit} = myers_edit_scripts(s1, s2)
          left_delta = Delta.changed(:node, :left, left, right, left_edit)
          right_delta = Delta.changed(:node, :right, left, right, right_edit)

          v2 = {
            SyntaxNode.next_sibling(left),
            SyntaxNode.next_sibling(right),
            [left_delta, right_delta]
          }

          add_edge(neighbors, v, v2)
        else
          add_changed_left_right(neighbors, v)
        end

      _ ->
        add_changed_left_right(neighbors, v)
    end
  end

  # When the parent is an unchanged binary operation, mark both nodes as
  # changed together to avoid arguments "sliding", e.g. `2 + 1` and `1 + 2`
  defp add_changed_edges(
         neighbors,
         {%{parent: {_, %{binary_op?: true}}} = left, right,
          %Delta{changed?: false, kind: :branch}} = v
       ) do
    v2 = {
      SyntaxNode.next_sibling(left),
      SyntaxNode.next_sibling(right),
      [Delta.changed(:node, :left, left, right), Delta.changed(:node, :right, left, right)]
    }

    add_edge(neighbors, v, v2)
  end

  defp add_changed_edges(neighbors, {left, right, _} = v) do
    # When nodes are similar branches, prevent marking them as separately
    # changed
    if SyntaxNode.similar_branch?(left, right) do
      neighbors
    else
      add_changed_left_right(neighbors, v)
    end

    # When nodes are similar branches, allow marking the branches as changed,
    # but ensure they're popped together
    # if SyntaxNode.similar_branch?(left, right) do
    #   left_delta = Delta.changed(:branch, :left, left, right)
    #   right_delta = Delta.changed(:branch, :right, left, right)

    #   v2 = {
    #     SyntaxNode.next_child(left, :pop_both),
    #     SyntaxNode.next_child(right, :pop_both),
    #     [left_delta, right_delta]
    #   }

    #   add_edge(neighbors, v, v2)
    # else
    #   add_changed_left_right(neighbors, v)
    # end
  end

  defp add_changed_left_right(neighbors, v) do
    neighbors
    |> add_changed_left(v)
    |> add_changed_right(v)
  end

  defp add_changed_left(neighbors, {left, %{null?: true} = right, _} = v) do
    add_edge(
      neighbors,
      v,
      {SyntaxNode.next_sibling(left), right, Delta.changed(:node, :left, left, right)}
    )
  end

  defp add_changed_left(neighbors, {%{branch?: true} = left, right, _} = v) do
    neighbors
    |> add_edge(
      v,
      {SyntaxNode.next_sibling(left), right, Delta.changed(:node, :left, left, right)}
    )
    |> add_edge(
      v,
      {SyntaxNode.next_child(left), right, Delta.changed(:branch, :left, left, right)}
    )
  end

  defp add_changed_left(neighbors, {%{branch?: false} = left, right, _} = v) do
    add_edge(
      neighbors,
      v,
      {SyntaxNode.next_sibling(left), right, Delta.changed(:node, :left, left, right)}
    )
  end

  defp add_changed_right(neighbors, {%{null?: true} = left, right, _} = v) do
    add_edge(
      neighbors,
      v,
      {left, SyntaxNode.next_sibling(right), Delta.changed(:node, :right, left, right)}
    )
  end

  defp add_changed_right(neighbors, {left, %{branch?: true} = right, _} = v) do
    neighbors
    |> add_edge(
      v,
      {left, SyntaxNode.next_sibling(right), Delta.changed(:node, :right, left, right)}
    )
    |> add_edge(
      v,
      {left, SyntaxNode.next_child(right), Delta.changed(:branch, :right, left, right)}
    )
  end

  defp add_changed_right(neighbors, {left, %{branch?: false} = right, _} = v) do
    add_edge(
      neighbors,
      v,
      {left, SyntaxNode.next_sibling(right), Delta.changed(:node, :right, left, right)}
    )
  end

  defp add_edge(neighbors, _v1, {left, right, delta}) do
    {left, right} = SyntaxNode.pop(left, right)
    [{{left, right, delta}, delta_cost(delta)} | neighbors]
  end

  defp delta_cost(%Delta{} = delta), do: Delta.cost(delta)
  defp delta_cost(list) when is_list(list), do: list |> Enum.map(&Delta.cost/1) |> Enum.sum()

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: nil}, delta}) do
    {l_id, r_id, delta_id(delta)}
  end

  defp vertex_id({%{id: l_id, parent: {entry, _}}, %{id: r_id, parent: nil}, delta}) do
    {l_id, r_id, entry, delta_id(delta)}
  end

  defp vertex_id({%{id: l_id, parent: nil}, %{id: r_id, parent: {entry, _}}, delta}) do
    {l_id, r_id, entry, delta_id(delta)}
  end

  defp vertex_id({%{id: l_id, parent: {e1, _}}, %{id: r_id, parent: {e2, _}}, delta}) do
    {l_id, r_id, e1, e2, delta_id(delta)}
  end

  defp delta_id(nil), do: nil
  defp delta_id(list) when is_list(list), do: Enum.map(list, &delta_id/1)
  defp delta_id(d), do: {d.changed?, d.side, d.left_node.id, d.right_node.id}

  defp myers_edit_scripts(s1, s2) do
    s1
    |> String.myers_difference(s2)
    |> Enum.reduce({[], []}, fn
      {:eq, s}, {left, right} -> {[{:eq, s} | left], [{:eq, s} | right]}
      {:del, s}, {left, right} -> {[{:changed, s} | left], right}
      {:ins, s}, {left, right} -> {left, [{:changed, s} | right]}
    end)
    |> then(fn {left, right} -> {Enum.reverse(left), Enum.reverse(right)} end)
  end

  defp debug?, do: !!System.get_env("DEBUG_DIFF")
  defp debug?(value), do: System.get_env("DEBUG_DIFF") == value

  defp debug_inspect(term, label) do
    IO.inspect(term, label: label, pretty: true, syntax_colors: IO.ANSI.syntax_colors())
  end

  @doc false
  def summarize_path(path), do: Enum.map(path, &summarize_delta/1)

  defp summarize_delta(%Delta{changed?: changed?, kind: :node, side: side} = delta) do
    node = Delta.node(delta)
    {changed?, side, :node, summarize_node(node)}
  end

  defp summarize_delta(%Delta{changed?: changed?, kind: :branch, side: side} = delta) do
    node = Delta.node(delta)

    ast =
      case SyntaxNode.ast(node) do
        {{:., _, _}, _, _} -> {{:., [], "..."}, [], "..."}
        {form, _, _} -> {form, [], "..."}
        {_, _} -> {"...", "..."}
        list when is_list(list) -> ["..."]
      end

    {changed?, side, :branch, ast}
  end

  defp summarize_delta(nil), do: nil

  defp summarize_node(%SyntaxNode{terminal?: true}), do: "TERMINAL"
  defp summarize_node(%SyntaxNode{null?: true}), do: "NULL"

  defp summarize_node(node) do
    node
    |> SyntaxNode.ast()
    |> AST.prewalk(fn
      {form, _meta, args} -> {form, [], args}
      quoted -> quoted
    end)
  end
end
