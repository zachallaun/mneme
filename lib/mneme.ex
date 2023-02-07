defmodule Mneme do
  @moduledoc """
  Snapshot testing for regular ol' Elixir code.

  Mneme helps you write tests by providing a replacement for ExUnit's
  `assert` called `auto_assert/1`. The difference between the two is
  simple: with `auto_assert`, you write the expression, and Mneme writes
  the assertion. Here's a basic example:

      test "drop_evens/1 should remove all even numbers from an enum" do
        auto_assert drop_evens(1..10)
        auto_assert drop_evens([])
        auto_assert drop_evens([:a, :b, 2, :c])
      end

  The first time you run this test, you'll receive three prompts asking
  if you'd like to update each of these expressions with a pattern
  matching their return value. After accepting, Mneme updates your test
  to look like this:

      test "drop_evens/1 should remove all even numbers from an enum" do
        auto_assert [1, 3, 5, 7, 9] <- drop_evens(1..10)
        auto_assert [] <- drop_evens([])
        auto_assert [:a, :b, :c] <- drop_evens([:a, :b, 2, :c])
      end

  The next time you run this test, you won't receive a prompt and these
  will act (almost) like any other assertion. See `auto_assert/1` for
  details on the differences from ExUnit's `assert`.

  ## Usage

  Spend less time typing out tests with these easy steps:

    1. Call `Mneme.start/0` in your `test/test_helper.exs`:

           ExUnit.start()
           Mneme.start()

    2. Add `use Mneme` anywhere you're using `ExUnit.Case`:

           defmodule MyAppTest do
             use ExUnit.Case
             use Mneme

             ...
           end

    3. Start using `auto_assert` instead of `assert` when writing tests:

           test "arithmetic" do
             auto_assert 2 + 2
           end

       Run this test and be dazzled by not having to type "3"!

  ## Configuration

  #{Mneme.Options.docs()}
  """

  @doc """
  Sets up Mneme to run auto-assertions in this module.
  """
  defmacro __using__(opts) do
    quote do
      import Mneme, only: [auto_assert: 1]
      require Mneme.Options
      Mneme.Options.register_attributes(unquote(opts))
    end
  end

  @doc """
  Configures the Mneme application server to run with ExUnit.
  """
  def start do
    ExUnit.configure(
      formatters: [Mneme.ExUnitFormatter],
      default_formatter: ExUnit.CLIFormatter,
      timeout: :infinity
    )

    children = [
      Mneme.Server
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc """
  Generates a new assertion or runs an existing one.

  ## Differences from ExUnit `assert`

  The `auto_assert` macro is meant to match `assert` as closely as
  possible. In fact, it generates ExUnit assertions under the hood.
  There are, however, a few small differences to note:

    * Pattern-matching assertions use the `<-` operator instead of the
      `=` match operator. Value-comparison assertions still use `==`
      (for instance, when the expression returns `nil` or `false`).

    * Guards can be added with a `when` clause, while `assert` would
      require a second assertion. For example:

          auto_assert pid when is_pid(pid) <- self()

          assert pid = self()
          assert is_pid(pid)

    * Bindings in an `auto_assert` are not available outside of that
      assertion. For example:

          auto_assert pid when is_pid(pid) <- self()

          # ERROR: pid is not bound
          pid

      If you need to use the result of the assertion, it will evaluate
      to the expression's value.

          pid = auto_assert pid when is_pid(pid) <- self()

          # pid is the result of self()
          pid
  """
  defmacro auto_assert(body) do
    code = {:auto_assert, Macro.Env.location(__CALLER__), [body]}
    Mneme.Assertion.build(code, __CALLER__)
  end
end
