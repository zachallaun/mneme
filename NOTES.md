# Notes

Strategy:

* `auto_assert` macro checks whether there's an assertion or not
* If no assertion, get the value and send it + metadata to a process that will collect all auto_assert stuff
* If there's an assertion, run it and if `ExUnit.AssertionError` is raised, get the value and send it + metadata to the collection process
* After tests have run, prompt user for each thing in some reasonable order and then patch all the files
* Use `ExUnit.Callbacks.on_exit/2` to do all the prompting at the end

## Guard syntax

Match operations don't support guards, e.g. the following isn't possible:

```elixir
x when is_integer(x) = 1
```

But since we control the `auto_assert` macro, we can translate something like the following:
```elixir
auto_assert %{x: x, y: y} when is_ref(x) and is_pid(y) = SomeModule.do_the_thing()

# transforms into assertions:

assert %{x: x, y: y} = SomeModule.do_the_thing
assert is_ref(x)
assert is_pid(y)
```

## Value diff

We may be able to use ExUnit's formatter to show a nice diff:

```elixir
IO.inspect(
  ExUnit.Formatter.format_assertion_diff(error, 0, :infinity, fn _, msg -> msg end)
)
```


## TODO / To Remember

- [ ] Shouldn't prompt if `CI` env var is set
- [ ] Should handle `=` and `==`, need to because `assert` still expects a truth value
- [ ] Add LICENSE prior to release
- [ ] Can we auto-detect things that should be pinned? We can use `Macro.Env.vars(__CALLER__)` to get available vars and compare in order to generate a pin match, e.g. `auto_assert %{ref: ^my_ref} = SomeModule.fun(my_ref)`
