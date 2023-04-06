defmodule Mneme do
  @external_resource "mix.exs"
  @external_resource "README.md"
  @mdoc "README.md"
        |> File.read!()
        |> String.split("<!-- MDOC !-->")
        |> Enum.fetch!(1)

  @moduledoc """
  /ni:mi:/ - Snapshot testing for Elixir ExUnit

  > #### Early days {: .info}
  >
  > Mneme is in its infancy and has an intentionally minimal API. Please
  > feel free to submit any feedback, bugs, or suggestions as
  > [issues on Github](https://github.com/zachallaun/mneme). Thanks!

  #{@mdoc}

  ## Configuration

  Certain behavior can be configured globally using application config
  or locally in test modules either at the module, describe-block, or
  test level.

  To configure Mneme globally, you can set `:defaults` for the `:mneme`
  application:

      config :mneme,
        defaults: [
          diff: :semantic
        ]

  These defaults can be overriden in test modules at various levels
  either as options to `use Mneme` or as module attributes.

      defmodule MyTest do
        use ExUnit.Case

        # reject all changes to auto-assertions by default
        use Mneme, action: :reject

        test "this test will fail" do
          auto_assert 1 + 1
        end

        describe "some describe block" do
          # accept all changes to auto-assertions in this describe block
          @mneme_describe action: :accept

          test "this will update without prompting" do
            auto_assert 2 + 2
          end

          # prompt for any changes in this test
          @mneme action: :prompt
          test "this will prompt before updating" do
            auto_assert 3 + 3
          end
        end
      end

  Configuration that is "closer to the test" will override more general
  configuration:

      @mneme > @mneme_describe > opts to use Mneme > :mneme app config

  The exception to this is the `CI` environment variable, which causes
  all updates to be rejected. See the "Continuous Integration" section
  for more info.

  ### Options

  #{Mneme.Options.docs()}
  """

  @doc """
  Sets up Mneme configuration for this module and imports auto-assertion
  macros.

  This macro accepts all options described in the "Configuration"
  section above.

  ## Example

      defmodule MyTest do
        use ExUnit.Case
        use Mneme # <- add this

        test "..." do
          auto_assert ...
        end
      end
  """
  defmacro __using__(opts) do
    quote do
      import Mneme, only: :macros
      require Mneme.Options
      Mneme.Options.register_attributes(unquote(opts))
    end
  end

  @doc """
  Asserts its argument is a valid pattern match, generating the pattern
  when needed.

  ## Examples

  `auto_assert` generates assertions when tests run, issuing a terminal
  prompt before making any changes (unless configured otherwise).

      auto_assert [1, 2] ++ [3, 4]

      # after running the test and accepting the change
      auto_assert [1, 2, 3, 4] <- [1, 2] ++ [3, 4]

  If the match no longer succeeds, a warning and new prompt will be
  issued to update it to the new value.

      auto_assert [1, 2, 3, 4] <- [1, 2] ++ [:a, :b]

      # after running the test and accepting the change
      auto_assert [1, 2, :a, :b] <- [1, 2] ++ [:a, :b]

  Prompts are only issued if the pattern doesn't match the value, so
  that pattern can also be changed manually.

      # this assertion succeeds, so no prompt is issued
      auto_assert [1, 2, | _] <- [1, 2] ++ [:a, :b]

  ## Differences from ExUnit `assert`

  The `auto_assert` macro is meant to match `assert` very closely, but
  there are a few differences to note:

    * Pattern-matching assertions use the `<-` operator instead of the
      `=` match operator.

    * Unlike ExUnit's `assert`, `auto_assert` can match falsy values.
      The following are equivalent:

          falsy = nil
          auto_assert nil <- falsy
          assert falsy == nil

    * Guards can be added with a `when` clause, while `assert` would
      require a second assertion. For example:

          auto_assert pid when is_pid(pid) <- self()

          assert pid = self()
          assert is_pid(pid)

    * Bindings in an `auto_assert` are not available outside of that
      assertion. For example:

          auto_assert pid when is_pid(pid) <- self()
          pid # ERROR: pid is not bound

      If you need to use the result of the assertion, it will evaluate
      to the expression's value.

          pid = auto_assert pid when is_pid(pid) <- self()
          pid # pid is the result of self()

  """
  defmacro auto_assert(arg) do
    ensure_in_test!(:auto_assert, __CALLER__)
    Mneme.Assertion.build(:auto_assert, [arg], __CALLER__)
  end

  @doc """
  Asserts that an exception is raised during `function` execution,
  generating the `exception` and `message` if needed.

  If the given function does not raise, the assertion will fail.

  Like `auto_assert/1`, you will be prompted to automatically update
  the assertion if the raised raised exception changes.

  ## Examples

  You can pass an anonymous function that takes no arguments and is
  expected to raise an exception.

      auto_assert_raise fn ->
        some_call_expected_to_raise()
      end

      # after running the test and accepting changes
      auto_assert_raise Some.Exception, fn ->
        some_call_expected_to_raise()
      end

      # optionally include the message
      auto_assert_raise Some.Exception, "perhaps with a message", fn ->
        some_call_expected_to_raise()
      end

  A captured function of arity zero can also be used.

      auto_assert_raise &some_call_expected_to_raise/0

      # after running the test and accepting changes
      auto_assert_raise Some.Exception, &some_call_expected_to_raise/0

  """
  defmacro auto_assert_raise(exception, message, function) do
    do_auto_assert_raise([exception, message, function], __CALLER__)
  end

  @doc """
  See `auto_assert_raise/3`.
  """
  defmacro auto_assert_raise(exception, function) do
    do_auto_assert_raise([exception, function], __CALLER__)
  end

  @doc """
  See `auto_assert_raise/3`.
  """
  defmacro auto_assert_raise(function) do
    do_auto_assert_raise([function], __CALLER__)
  end

  defp do_auto_assert_raise(args, caller) do
    ensure_in_test!(:auto_assert_raise, caller)
    Mneme.Assertion.build(:auto_assert_raise, args, caller)
  end

  @doc """
  Starts Mneme to run auto-assertions as they appear in your tests.

  This will almost always be added to your `test/test_helper.exs`, just
  below the call to `ExUnit.start()`:

      # test/test_helper.exs
      ExUnit.start()
      Mneme.start()

  ## Options

    * `:restart` (boolean) - Restarts Mneme if it has previously been
      started. This option enables certain IEx-based testing workflows
      that allow tests to be run without a startup penalty. Defaults to
      `false`.

  """
  def start(opts \\ []) do
    ExUnit.configure(
      formatters: [Mneme.Server.ExUnitFormatter],
      default_formatter: ExUnit.CLIFormatter,
      timeout: :infinity
    )

    Mneme.Options.configure()

    if opts[:restart] && Process.whereis(Mneme.Supervisor) do
      _ = Supervisor.terminate_child(Mneme.Supervisor, Mneme.Server)
      {:ok, _pid} = Supervisor.restart_child(Mneme.Supervisor, Mneme.Server)
    else
      children = [
        Mneme.Server
      ]

      opts = [
        name: Mneme.Supervisor,
        strategy: :one_for_one
      ]

      Supervisor.start_link(children, opts)
    end

    :ok
  end

  defp ensure_in_test!(call, caller) do
    with {fun_name, 1} <- caller.function,
         "test " <> _ <- to_string(fun_name) do
      :ok
    else
      _ -> raise Mneme.CompileError, message: "#{call} can only be used inside of a test"
    end
  end
end
