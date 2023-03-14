# Diff notes

References:

* [Difftastic](https://difftastic.wilfred.me.uk/)
* [`ExUnit.Diff.to_algebra/2`](https://github.com/elixir-lang/elixir/blob/v1.14.3/lib/ex_unit/lib/ex_unit/diff.ex#L907)

I'd like to try providing a semantic diff based on [Difftastic](https://github.com/Wilfred/difftastic), where the diff highlights the semantic changes to the value, not just the literal character changes.

Since the data values are always some kind of data literal (+ guards), we can start with a simplified version that doesn't have to understand the entire Elixir AST and can ignore certain things like comments. This should hopefully simplify the problem enough that I can get a first working version.

## Syntax to care about

Consider using the "normalized AST" that Sourceror proposed a while back, [found here](https://github.com/doorgan/sourceror/blob/9cdebddd3b8894772528e4411235e57cad35014c/guides/sourceror_ast.md).

We'd need to be able to convert to/from that AST to what Sourceror/Elixir expects.

    # guards
    foo when is_bar(foo) and is_baz(foo)

    # basic data literals
    1_000
    1_000.5
    :atoms
    :"atoms-with-special-chars"
    "string"
    """
    heredocs
    """

    # special atoms
    true
    false
    nil

    # lists
    [:foo, :bar, :baz]
    'charlists'

    # tuples
    {:two, :elements}
    {:three, :or, :more} # different ast representation

    # binaries
    <<1, 2, 3>>

    # maps
    %{keyword: 1, maps: 2}
    %{"mixed key" => 1, :maps => 2}

    # structs
    %MyStruct{foo: 1, bar: 2}

    # variables & pins
    var
    ^var

## Misc cases

Map to struct with same keys only highlights the addition of the alias.

    %{foo: 1, bar: 2}
    # =>
    %MyStruct{foo: 1, bar: 2}
     ^^^^^^^^

Adding a non-keyword key to a map with only keywords only highlights the new key. (The map syntax may change from `:` to `=>`, but the kv's haven't changed.)

    %{foo: 1, bar: 2}
    # =>
    %{:foo => 1, :bar => 2, "baz" => 3}
                            ^^^^^^^^^^

Changing delimiters, e.g. from keyword list to map, only highlights the old/new delimiters.

    [foo: 1, bar: 2]
    ^              ^
    # =>
    %{foo: 1, bar: 2}
    ^^              ^

## Graph edges

Difftastic's [graph.rs](https://github.com/Wilfred/difftastic/blob/master/src/diff/graph.rs) shows how they represent operations as graph edges:

* UnchangedNode (depth_difference)
* EnterUnchangedDelimiter (depth_difference)
* NovelAtomLHS (contiguous, probably_punctuation)
* NovelAtomRHS (contiguous, probably_punctuation)
* EnterNovelDelimiterLHS (contiguous)
* EnterNovelDelimiterRHS (contiguous)
* ReplacedComment (levenshtein_pct)

The edges are weighted when they are generated in [`get_set_neighbours`](https://github.com/Wilfred/difftastic/blob/master/src/diff/graph.rs#L478), which also computes which edges are allowed from a given vertex (there are certain rules for entering delimiters).

After lazily constructing the graph and finding the shortest weighted path using Dijkstra's, Difftastic walks the path for both versions of the syntax and constructs:

* Unchanged
* Novel
* ReplacedComment

Novel means a deletion for the old code and an insertion for the new code.

### Mneme differences

Expected differences to Difftastic:

* We're going to ignore the ReplacedComment edge/change for our purposes.

* We'll eagerly construct the entire graph since we're always diffing a relatively small bit of code, but we can switch to a lazy pathfinding algorithm that constructs it as we go if needed.

* Punctuation (primarily commas) might be ignored, since we're using Elixir's AST and not something like treesitter that has punctuation info. We could theoretically still add highlighting to punctuation, but we won't have nodes for them.
