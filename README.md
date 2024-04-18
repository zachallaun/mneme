# /ˈniːmiː/ - Snapshot testing utilities for Elixir

[![Hex.pm](https://img.shields.io/hexpm/v/mneme.svg)](https://hex.pm/packages/mneme)
[![Docs](https://img.shields.io/badge/hexdocs-docs-8e7ce6.svg)](https://hexdocs.pm/mneme)
[![CI](https://github.com/zachallaun/mneme/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/zachallaun/mneme/actions/workflows/ci.yml)

<p data-video>https://gist.github.com/assets/503938/3155b333-6a59-448e-8735-dc0093bd677e</p>

Mneme augments `ExUnit.Assertions` with a set of assertions that know how to update themselves.
This is sometimes called snapshot, approval, or golden master testing.

With Mneme, you write something like...

```elixir
auto_assert my_function()
```

...and next time you run your tests, Mneme:

1. runs the code and generates a pattern from the returned value, then
2. prints a diff and prompts you to confirm the change.

Now your test looks like this:

```elixir
auto_assert %MyAwesomeValue{so: :cool} <- my_function()
```

This lets you quickly write lots of tests, and like ordinary tests, you'll see a diff when they fail.
But, unlike ordinary tests, you can choose to accept the changes and Mneme will rewrite the test for you.

**Features:**

  * **Auto-updating assertions:** maintain correct tests as behavior changes during development.
  * **Alternatives to familiar assertions** `auto_assert`, `auto_assert_raise`, `auto_assert_receive`, `auto_assert_received`.
  * **Seamless integration with ExUnit:** no need to change your workflow, just run `mix test`.
  * **Interactive prompts in your terminal** when a new assertion is added or an existing one changes.
  * **Syntax-aware diffs** highlight the meaningful changes in a value.

**Take a brief tour:**

If you'd like to see Mneme in action, you can download and run [examples/tour_mneme.exs](https://github.com/zachallaun/mneme/blob/main/examples/tour_mneme.exs), a standalone tour that only requires that you have Elixir installed.

```shell
$ curl -o tour_mneme.exs https://raw.githubusercontent.com/zachallaun/mneme/main/examples/tour_mneme.exs

$ elixir tour_mneme.exs
```

## Quickstart

1.  Add `:mneme` do your deps in `mix.exs`:

    ```elixir
    defp deps do
      [
        {:mneme, ">= 0.0.0", only: [:dev, :test]}
      ]
    end
    ```

2.  Add `:mneme` to your `:import_deps` in `.formatter.exs`:

    ```elixir
    [
      import_deps: [:mneme],
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    ```

3.  Start Mneme right after you start ExUnit in `test/test_helper.exs`:

    ```elixir
    ExUnit.start()
    Mneme.start()
    ```

4.  Add `use Mneme` wherever you `use ExUnit.Case`:

    ```elixir
    defmodule MyTest do
      use ExUnit.Case, async: true
      use Mneme

      test "arithmetic" do
        auto_assert 2 + 2
      end
    end
    ```

5.  Run `mix test` and type `y<ENTER>` when prompted; your test should look like:

    ```elixir
    defmodule MyTest do
      use ExUnit.Case, async: true
      use Mneme

      test "arithmetic" do
        auto_assert 4 <- 2 + 2
      end
    end
    ```

## Requirements

### Elixir

Mneme requires Elixir version 1.14 or later.

### Formatter

**If you do not use a formatter, the first auto-assertion will reformat the entire file,** introducing unrelated formatting changes.
Mneme rewrites your test scripts when updating an assertion using the formatter configuration for your project.

It's highly recommended to configure your editor to format Elixir files on-save.

Note: Mneme uses [`Rewrite`](https://github.com/hrzndhrn/rewrite) to update files, which supports the [Elixir formatter](https://hexdocs.pm/mix/Mix.Tasks.Format.html) and [`FreedomFormatter`](https://github.com/marcandre/freedom_formatter).

## Command line interface

Auto-assertions are run with your normal tests when you run `mix test` and a terminal prompt is used whenever one needs to be updated.
Here's what that might look like:

![Screenshot of Mneme CLI](https://github.com/zachallaun/mneme/blob/main/docs/assets/images/demo_screenshot.png?raw=true)

Whenever that happens, you have a few options:

|Key|Action|Description|
|-|-|-|
|`y`|Accept|Accept the proposed change. The assertion will be re-run and should pass.|
|`n`|Reject|Reject the proposed change and fail the test.|
|`s`|Skip|Skip this assertion. The test will not fail, but the `mix test` process will exit with `1`.|
|`k`|Next|If multiple patterns have been generated, cycle to the next one.|
|`j`|Previous|If multiple patterns have been generated, cycle to the previous one.|

Note that the CLI is not available when tests are run in a CI environment.
See the [Continuous Integration](#continuous-integration) section for more info.

## Generated patterns

Mneme tries to generate match patterns that are close to what you would write.
Basic data types like numbers, lists, tuples, and strings will generate as you would expect.
For maps and structs, Mneme will often give you a couple of options.
For values without a literal representation, like pids, guards will be used.

```elixir
auto_assert pid when is_pid(pid) <- self()
```

Additionally, local bindings can be found and pinned as a part of patterns.
This keeps the number of "magic values" down and makes tests more robust.

```elixir
test "create_post/1 creates a new post with valid attrs", %{user: user} do
  valid_attrs = %{title: "my_post", author: user}

  auto_assert create_post(valid_attrs)
end

# generates:

test "create_post/1 creates a new post with valid attrs", %{user: user} do
  valid_attrs = %{title: "my_post", author: user}

  auto_assert {:ok, %Post{title: "my_post", author: ^user}} <- create_post(valid_attrs)
end
```

### Special patterns

This is a non-exhaustive list of things Mneme takes into consideration when generating match patterns:

  * Pinned variables are generated by default if a value is equal to a variable in scope.

  * Date and time values are written using their sigil representation.

  * Struct patterns only include fields that are different from the struct defaults.

  * Structs defined by Ecto schemas exclude primary keys, association foreign keys, and auto generated fields like `:inserted_at` and `:updated_at`. This is because these fields are often randomly generated and would fail on subsequent tests.

## Continuous Integration

In a CI environment, Mneme will not attempt to prompt and update any assertions, but will instead fail any tests that would update.
This behavior is enabled by the `CI` environment variable, which is set by convention by many continuous integration providers.

```bash
export CI=true
```

## Editor support

Guides for optional editor integration can be found here:

  * [VS Code](https://hexdocs.pm/mneme/vscode_setup.html)

## Links and acknowledgements

Special thanks to:

  * [_What if writing tests was a joyful experience?_](https://blog.janestreet.com/the-joy-of-expect-tests/), from the Jane Street Tech Blog, for inspiring this library.

  * [_My Kind of REPL_](https://ianthehenry.com/posts/my-kind-of-repl/), an article by Ian Henry that shows how snapshot testing can change your workflow.

  * [Sourceror](https://github.com/doorgan/sourceror), a library that makes complex code modifications simple.

  * [Rewrite](https://github.com/hrzndhrn/rewrite), which makes updating source code a breeze.

  * [Owl](https://github.com/fuelen/owl), which makes it much easier to build a pretty CLI.

  * [Insta](https://insta.rs/), a snapshot testing tool for Rust, whose great documentation provided an excellent reference for snapshot testing.

  * [assert_value](https://github.com/assert-value/assert_value_elixir), an existing Elixir project that provides similar functionality.
