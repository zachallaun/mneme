# /ˈniːmiː/ - Snapshot testing utilities for Elixir

<details>
  <summary>🎥 Video Demo</summary>
  <p>https://user-images.githubusercontent.com/503938/227819477-c7097fbc-b9a4-44a1-b3ea-f1b420c18799.mp4</p>
</details>

---

**Note:** This README tracks the `main` branch.
See the HexDocs linked below for documentation for the latest release.

---

<!-- MDOC !-->

[![Hex.pm](https://img.shields.io/hexpm/v/mneme.svg)](https://hex.pm/packages/mneme)
[![Docs](https://img.shields.io/badge/hexdocs-docs-8e7ce6.svg)](https://hexdocs.pm/mneme)
[![CI](https://github.com/zachallaun/mneme/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/zachallaun/mneme/actions/workflows/ci.yml)

Mneme provides a set of familiar assertions that automate the tedious parts of testing.

This is sometimes called snapshot testing or approval testing, but that's not particulary important.

With Mneme, you write something like

```elixir
auto_assert my_function()
```

and next time you run your tests, Mneme runs the function, generates a pattern from the returned value, updates the assertion, and prompts you to confirm it's what you expected.
Now you have:

```elixir
auto_assert %MyAwesomeValue{so: :cool} <- my_function()
```

This lets you quickly write lots of tests to ensure the behavior of your program doesn't change without you knowing.
And if it does, Mneme prompts you with a diff so you can easily see what's up.

**Features:**

  * **Automatically-maintained assertions:** compare values using `auto_assert`, test exceptions using `auto_assert_raise`, or test process messages using `auto_assert_receive` and friends.
  * **Seamless integration with ExUnit:** no need to change your workflow, just run `mix test`.
  * **Interactive prompts in your terminal** when a new assertion is added or an existing one changes.
  * **Syntax-aware diffs** highlight the meaningful changes in a value.
  * **Pattern matching** auto-assertions let you assert on the parts of a value that matter and ignore the rest.

## A brief example

Let's say we're working on a function that removes even numbers from a list:

```elixir
test "drop_evens/1 should remove all even numbers from an enum" do
  auto_assert drop_evens(1..10)

  auto_assert drop_evens([])

  auto_assert drop_evens([:a, :b, 2, :c])
end
```

We're using `auto_assert` and only writing the expressions we wish to test.
The first time we run `mix test`, Mneme generates patterns and prompts you with diffs.
When you accept them, your test is updated automatically:

```elixir
test "drop_evens/1 should remove all even numbers from an enum" do
  auto_assert [1, 3, 5, 7, 9] <- drop_evens(1..10)

  auto_assert [] <- drop_evens([])

  auto_assert [:a, :b, :c] <- drop_evens([:a, :b, 2, :c])
end
```

The next time you run your tests, you won't receive prompts (unless something changes!), and these auto-assertions will act like a normal `assert`.
If things _do_ change, you're prompted again and can choose to accept and update the test or reject the change and let it fail.

## A brief tour

To see Mneme in action without adding it to a project, you can download and run the standalone tour:

```shell
$ curl -o tour_mneme.exs https://raw.githubusercontent.com/zachallaun/mneme/main/examples/tour_mneme.exs

$ elixir tour_mneme.exs

 Tour  Welcome to the Mneme Tour! We're going to run through some tests using
       Mneme's auto-assertions.

       We're going to be testing a basic HTTP request parser. Here's how it
       might be called:

           parse_request("GET /path HTTP/1.1\n")

       Let's see what happens when we auto_assert that expression.

       continue ⏎
```

## Quick start

1.  Add `:mneme` do your deps in `mix.exs`:

    ```elixir
    defp deps do
      [
        {:mneme, ">= 0.0.0", only: :test}
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
        # use auto_assert instead of ExUnit's assert - run this test
        # and delight in all the typing you don't have to do
        auto_assert 2 + 2
      end
    end
    ```

## Pattern matching

Snapshot testing is a powerful tool, allowing you to ensure that your code behaves as expected, both now and in the future.
However, traditional snapshot testing can be brittle, breaking whenever there is any change, even ones that are inconsequential to what is being tested.

Mneme addresses this by introducing Elixir's pattern matching to snapshot testing.
With pattern matching, tests become more flexible, only failing when a change affects the expected structure.
This allows you to focus on changes that matter, saving time and reducing noise in tests.

To facilitate this, Mneme generates the patterns that you were likely to have written yourself.
If a value contains some input variable in its structure, Mneme will try to use a pinned variable (e.g. `^date`).
If the value is an Ecto struct, Mneme will omit autogenerated fields like timestamps that are likely to change with every run.
And if Mneme doesn't get it quite right, you can update the pattern yourself — you won't be prompted unless the pattern no longer matches.

## Generated patterns

Mneme tries to generate match patterns that are equivalent to what a human (or at least a nice LLM) would write.
Basic data types like strings, numbers, lists, tuples, etc. will be as you would expect.

Some values, however, do not have a literal representation that can be used in a pattern match.
Pids are such an example.
For those, guards are used:

```elixir
auto_assert self()

# generates:

auto_assert pid when is_pid(pid) <- self()
```

Additionally, local variables can be found and pinned as a part of the
pattern. This keeps the number of hard-coded values down, reducing the
likelihood that tests have to be updated in the future.

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

In many cases, multiple valid patterns will be possible. Usually, the
"simplest" pattern will be selected by default when you are prompted,
but you can cycle through the options as well.

### Non-exhaustive list of special cases

  * Pinned variables are generated by default if a value is equal to a
    variable in scope.

  * Date and time values are written using their sigil representation.

  * Struct patterns only include fields that are different from the
    struct defaults.

  * Structs defined by Ecto schemas exclude primary keys, association
    foreign keys, and auto generated fields like `:inserted_at` and
    `:updated_at`. This is because these fields are often randomly
    generated and would fail on subsequent tests.

## Formatting

Mneme uses [`Rewrite`](https://github.com/hrzndhrn/rewrite) to update
source code, formatting that code before saving the file. Currently,
the Elixir formatter and `FreedomFormatter` are supported. **If you do
not use a formatter, the first auto-assertion will reformat the entire
file.**

## Continuous Integration

In a CI environment, Mneme will not attempt to prompt and update any
assertions, but will instead fail any tests that would update. This
behavior is enabled by the `CI` environment variable, which is set by
convention by many continuous integration providers.

```bash
export CI=true
```

## Editor support

Guides for optional editor integration can be found here:

  * [VS Code](https://hexdocs.pm/mneme/vscode_setup.html)

## Acknowledgements

Special thanks to:

  * [_What if writing tests was a joyful experience?_](https://blog.janestreet.com/the-joy-of-expect-tests/),
    from the Jane Street Tech Blog, for inspiring this library.

  * [Sourceror](https://github.com/doorgan/sourceror), a library that
    makes complex code modifications simple.

  * [Rewrite](https://github.com/hrzndhrn/rewrite), which provides the
    diff functionality present in Mneme.

  * [Owl](https://github.com/fuelen/owl), which makes it much easier
    to build a pretty CLI.

  * [Insta](https://insta.rs/), a snapshot testing tool for Rust,
    whose great documentation provided an excellent reference for
    snapshot testing.

  * [assert_value](https://github.com/assert-value/assert_value_elixir),
    an existing Elixir project that provides similar functionality.
    Thank you for paving the way!

<!-- MDOC !-->

## Configuration

See the [full module documentation](https://hexdocs.pm/mneme/Mneme.html#module-configuration) for configuration options.
