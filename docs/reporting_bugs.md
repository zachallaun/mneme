# Reporting Bugs

I greatly appreciate reports for any and all issues you encounter using Mneme.
When reporting a bug, providing a reproduction makes things much easier to address.

Thankfully, Elixir's `Mix.install([...])` makes it possible to standalone scripts that include dependencies.
When possible, use this to create a single script that reproduces the bug.

```elixir
# repro.exs

Mix.install([
  # use exact versions from your mix.lock
  {:mneme, "0.6.0"},
  ...
])

ExUnit.start()
Mneme.start()

# any other modules needed to reproduce
defmodule MyModule do
  ...
end

# test module that reproduces the bug
defmodule Repro do
  use ExUnit.Case
  use Mneme

  test "reproduction" do
    ...
  end
end

ExUnit.run()
```

When written this way, reproducing the error should now be as simple as running `elixir repro.exs`.
