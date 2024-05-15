# Pattern generation

When new auto-assertions are written or when returned values are changed, Mneme rewrites your assertion.
We call this *pattern generation*.

This page documents the kinds of patterns Mneme generates and why.

![Screenshot of new pattern](https://github.com/zachallaun/mneme/blob/main/docs/assets/images/demo_screenshot.png?raw=true)

## Multiple patterns

For any given auto-assertion, multiple patterns may be generated, in which case you will have the ability to "scroll" through them and select the one that best represents what you care to assert.

For instance, imagine you are testing a `MessageBoard.create_post/1` function.
It may be sufficient to simply assert that a post was created:

```elixir
test "create_post/1 creates a new post with valid attrs", %{user: user} do
  attrs = %{content: "my post", author: user}

  auto_assert {:ok, %Post{}} <- MessageBoard.create_post(attrs)
end
```

Or you may want to match on additional attributes of the post itself:

```elixir
test "create_post/1 creates a new post with valid attrs", %{user: user} do
  attrs = %{content: "my post", author: user}

  auto_assert {:ok, %Post{content: "my post", author: ^user}} <-
                MessageBoard.create_post(attrs)
end
```

Either of these might be what you want, so instead of picking for you, Mneme would generate both, and give you the option between them.

### Default selection

Multiple patterns are generally ordered from simple to complex and the one that is selected by default depends on the `:default_pattern` option.
(You can find more information about configuring Mneme [here](`Mneme#module-configuration`).)

The default value for `:default_pattern` is `:infer`, which essentially means:

  * If the pattern is for a new assertion, the first (simplest) pattern will be selected.
  * If an existing pattern is being updated, a _similar_ pattern will be selected first.

Using the `MessageBoard.create_post/1` test above as an example, consider what might happen if the content of the post changes:

```elixir
test "create_post/1 creates a new post with valid attrs", %{user: user} do
  # :content attribute has been updated
  attrs = %{content: "my NEW post", author: user}

  # next time this runs, Mneme will ask to update this assertion
  auto_assert {:ok, %Post{content: "my post", author: ^user}} <-
                MessageBoard.create_post(attrs)
end
```

If the `:default_pattern` was `:first`, the default selected pattern would be `{:ok, %Post{}}`, but this is unlikely to be what you want.
Using `:infer`, the default pattern would be the same as above, with only the `:content` of the post changed.

While you won't often have to change `:default_pattern`, there is one trick that can be used to very quickly iterate on some code:

```elixir
@mneme default_pattern: :last, force_update: true, action: :accept
test "dev" do
  auto_assert something_being_worked_on(:foo)
  auto_assert something_being_worked_on(:bar)
end
```

This combination of options means that, whenever that test is run, Mneme will immediately update the pattern without prompting.
With your tests bound to a [keyboard shortcut](vscode_setup.html#keyboard-shortcuts), this can be a very quick way to see what your code is returning.

## Basic data types

These data types have no special handling and use their equivalent data literal in patterns:

  * atoms
  * integers
  * floats
  * tuples

> #### -0.0 in Erlang/OTP 27 {: .warning}
>
> In Erlang/OTP 27, [`0.0` will no longer match `-0.0`](https://www.erlang.org/docs/26/general_info/upcoming_incompatibilities#0.0-and--0.0-will-no-longer-be-exactly-equal).
> Mneme does not currently handle this and will always generate the pattern `+0.0`.
> Support for `-0.0` patterns will be added at a future date.

## Lists and charlists

List patterns are generated using square brackets.
However, if the list contains only ASCII-printable integers, it will be identified as a charlist and an additional pattern using `sigil_c/2` will be suggested:

```elixir
# this assertion...
auto_assert Enum.map([2, 11, 11], &(&1 + 100))

# ... would suggest these two patterns
auto_assert [102, 111, 111] <- Enum.map([2, 11, 11], &(&1 + 100))
auto_assert ~c"foo" <- Enum.map([2, 11, 11], &(&1 + 100))
```

## Strings and binaries

Patterns for strings and binaries follow these rules:

  * If the string is not printable, a bitstring pattern using `<<>>` is generated.
  * If the string is printable, a pattern using `"` is generated.
  * If the string is printable and contains a newline, a heredoc pattern using `"""` is generated.

## Maps

For new assertions, map patterns will always include all of the keys present in the map.
When updating an existing assertion, however, a pattern using fewer keys will be generated if the existing pattern excludes some keys.
For example:

```elixir
# if this value...
auto_assert %{x: 1} <- %{x: 1, y: 2, z: 3}

# ... is updated to...
auto_assert %{x: 1} <- %{x: 10, y: 20, z: 30}

# ... then the default suggested pattern would only include :x
auto_assert %{x: 10} <- %{x: 10, y: 20, z: 30}
```

## Structs

Most structs are similar to maps, with the exception that empty struct patterns like `%MyStruct{}` will be generated even if the struct has fields, while empty map patterns like `%{}` are not (unless the map is truly empty).
This is done because it is often useful to assert that a struct of some kind was returned without asserting its content.

### Struct shorthands

Some built-in structs have preferred syntax or sigil representations that can be used as patterns.
These include:

  * `Range` - `1..10`
  * `Regex` - `~r/abc/`
  * `DateTime` - `~U[2024-01-01 12:00:00Z]`
  * `NaiveDateTime` - `~N[2024-01-01 12:00:00]`
  * `Date` - `~D[2024-01-01]`
  * `Time` - `~T[12:00:00]`

### Ecto structs

If the struct was defined using `Ecto.Schema`, additional fields will be excluded from the pattern:

  * Primary keys like `id`
  * Autogenerated fields like `inserted_at` and `updated_at`
  * Unloaded associations

This is done because these fields are unstable and generating a pattern with them would cause the test to update every time it is run.

## PIDs, references, ports, and functions

Some non-serializable data types do not have a data-literal representation and require guards in order to match on them.
Mneme will generate patterns using guards for PIDs, references, ports, and functions.
For example:

```elixir
# this assertion...
auto_assert self()

# ... will generate this pattern
auto_assert pid when is_pid(pid) <- self()
```

## Pinned variables

Mneme will use the pin operator `^/1` if a value or element in a collection is the same as a variable currently in scope.

```elixir
ref = make_ref()

# this assertion...
auto_assert Map.put(%{}, :ref, ref)

# ... will generate this pattern
auto_assert `%{ref: ^ref} <- Map.put(%{}, :ref, ref)
```
