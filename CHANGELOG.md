# Changelog

This format is based on [Keep a Changelog](https://keepachangelog.com) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.10.2 (2025-01-24)

### Changed

  * [@JonasGruenwald](https://github.com/JonasGruenwald) - Support [Igniter](https://hexdocs.pm/igniter/readme.html) versions 0.5.0+ ([#106](https://github.com/zachallaun/mneme/issues/106)).

## v0.10.1 (2024-12-17)

### Fixed

  * Fixed a crash that occurred when generating patterns for improper lists ([#105](https://github.com/zachallaun/mneme/issues/105)).

## v0.10.0 (2024-11-07)

### Added

  * `mix mneme.test`, which is functionally equivalent to `mix test` except that it allows Mneme's configuration options to be passed at the command line.

### Changed

  * `mix mneme.watch` now uses `mix mneme.test` under the hood so that it can accept the same options.
    * This means that `mneme.test` needs to be added to your `:preferred_cli_env` in `mix.exs`: `preferred_cli_env: ["mneme.test": :test, "mneme.watch": :test]`.
    * Running `MIX_ENV=test mix mneme.install` will update this for you.

### Fixed

  * Ensure that the module is loaded before generating struct patterns ([#102](https://github.com/zachallaun/mneme/issues/102)).
  * If an existing string pattern is using `"""`, use the same by default if the string changes ([#80](https://github.com/zachallaun/mneme/issues/80)).

## v0.9.4 (2024-10-28)

### Added

  * `mix mneme.install`, an [Igniter](https://github.com/ash-project/igniter) task that simplifies setup.

## v0.9.3 (2024-10-21)

### Fixed

  * Don't simplify structs used as keys in maps ([#96](https://github.com/zachallaun/mneme/issues/96)).
  * [mix mneme.watch] Ensure the `:ex_unit` application is started before accessing its application config ([#95](https://github.com/zachallaun/mneme/issues/95)).

## v0.9.2 (2024-10-14)

### Added

  * Added `--exit-on-success` flag to `mix mneme.watch`, which reruns tests until all of them pass, then exits.

### Fixed

  * Prevent an increasing number of "Running ExUnit with seed..." messages from printing during runs of `mix mneme.watch`. This was a regression introduced in v0.9.1.

## v0.9.1 (2024-10-14)

### Fixed

  * Don't override existing ExUnit formatters ([#87](https://github.com/zachallaun/mneme/issues/87)).

## v0.9.0 (2024-10-08)

### Added

  * `mix mneme.watch`, a test runner that watches source files for changes and automatically re-runs your tests. It's Mneme-aware, which means it can interrupt prompts and save already-accepted tests if a file system change is detected mid-run.

### Fixed

  * Fix crash that could occur when generating heredoc strings with repeated newlines ([#85](https://github.com/zachallaun/mneme/issues/85)).

## v0.8.2 (2024-07-11)

### Added

  * Added `J` and `K` to jump to the first and last pattern when multiple patterns are offered in a prompt. (`J` and `K` were previously equivalent to `j` and `k`, respectively.)

### Fixed

  * Don't suggest duplicate patterns when updating lists (or other containers of) maps.
  * Don't generate incorrect map patterns when updating an existing pattern that is a partial match of a new value. For instance, when updating the pattern `%{x: 1, y: 2, z: 3}` for the new value `%{x: 1, y: 2}`, the incorrect pattern `%{x: 1, y: 2, z: nil}` would be suggested.

## v0.8.1 (2024-06-20)

### Fixed

  * Fix a diff bug that could cause some deleted or added code to go unhighlighted.

## v0.8.0 (2024-06-20)

### Added

  * [@am-kantox](https://github.com/am-kantox) - Variables bound in `auto_assert` patterns remain in scope ([#1](https://github.com/zachallaun/mneme/issues/1)).
  * Print a warning when an auto-assertion that will always succeed is encountered.

## v0.7.0 (2024-05-27)

This is the first version supporting Elixir 1.17.0 and Erlang/OTP 27.

### Changed

  * Update docs to reflect `-0.0` being a possible generated value when using Erlang/OTP 27 or later.

### Fixed

  * Fix diff highlighting of the map opening delimiter `%{` when using Elixir 1.17+.
  * Fix warnings during testing when using Elixir 1.17+.

## v0.6.1 (2024-05-21)

### Added

  * Update map and struct patterns that ignore keys more intelligently, e.g. `%{x: 1, y: _}` will now still use `_` for `:y` when `:x` changes.

### Fixed

  * Fix a crash that would occur when generating a pattern for a non-existing struct, e.g. `%{__struct__: Foo}` when `Foo` is not a module defining a struct ([#67](https://github.com/zachallaun/mneme/issues/67)).
  * Generate the signed pattern `+0.0` for the float `0.0` to avoid the warning about `+0.0` and `-0.0` no longer matching in Erlang/OTP 27. (Mneme will gain support for generating `-0.0` patterns in the future.)

## v0.6.0 (2024-04-15)

### Changed

  * Calling `Mneme.start/1` multiple times now has the same behavior as `Mneme.start(restart: true)`. The `:restart` option is now a no-op and specifying it will print a notice.

### Fixed

  * Tests using Mneme can now be compiled individually without having first called `Mneme.start/1`. Previously, an error would be raised at compile-time, interfering with some language servers ([lexical-lsp/lexical#507](https://github.com/lexical-lsp/lexical/issues/507)).

## v0.5.1 (2024-04-13)

### Changed

  * Updated some dependencies for better compatibility with other libraries.

## v0.5.0 (2024-02-06)

While this release does not include breaking changes, the minor version is being bumped because the change to map patterns described below may be unexpected.

### Changed

  * Empty maps will no longer be suggested as patterns for non-empty maps. For instance, `auto_assert %{foo: 1}` will no longer suggest `auto_assert %{} <- %{foo: 1}`. Note that empty structs will still be suggested ([#55](https://github.com/zachallaun/mneme/issues/55), [#56](https://github.com/zachallaun/mneme/issues/56), [#57](https://github.com/zachallaun/mneme/issues/57)).

### Fixed

  * Generate struct patterns for `DateTime` when the sigil cannot be used ([#59](https://github.com/zachallaun/mneme/issues/59)).
  * Correctly escape non-printable characters in string literals, like `\r` ([#62](https://github.com/zachallaun/mneme/issues/62)).
  * Fix a crash that could occur due to incorrect handling of the source file being changed while Mneme was running.

## v0.4.3 (2023-11-02)

### Fixed

  * Fix a regression introduced in v0.4.1 that caused auto-assertions to fail if an earlier one in the same file added or removed lines when formatted ([#53](https://github.com/zachallaun/mneme/issues/53)).
  * Suppress "unused alias" warnings when the aliases are only used in auto-assertions ([#54](https://github.com/zachallaun/mneme/issues/54)).

## v0.4.2 (2023-11-01)

### Fixed

  * Fix a crash that would occur if a test file containing an auto-assertion is changed before the auto-assertion is run (for instance, while Mneme is waiting on input from an auto-assertion in a different test file).

## v0.4.1 (2023-10-25)

### Fixed

  * Fix a crash that could occur when diffing sigils ([#52](https://github.com/zachallaun/mneme/issues/52)).

## v0.4.0 (2023-07-04)

### Added

  * `Mneme.start/1` now accepts all of Mneme's configuration options that will be applied to the entire test run.

### Removed

  * **Breaking:** Removed support for `:mneme` application config. This has been replaced by passing config options directly to `Mneme.start/1`:

      ```elixir
      # Old: config/test.exs
      config :mneme, defaults: [default_pattern: :last, ...]

      # New: test/test_helper.exs
      Mneme.start(default_pattern: :last, ...)
      ```

## v0.3.5 (2023-06-30)

### Fixed

  * Support multi-letter sigils when using Elixir 1.15.0+.

## v0.3.4 (2023-05-22)

### Added

  * Tested to support OTP 26.0 when using Elixir 1.14.4.
  * Support expressions that return functions, serializing them with an `is_function(fun, arity)` guard.
  * When generating a pattern for a MapSet, add a note suggesting using `MapSet.to_list/1` for better serialization.

### Changed

  * Format pattern notes to be more obvious when they're present.
  * Generate charlist patterns using `sigil_c` instead of single quotes, e.g. `~c"foo"` instead of `'foo'`. See [this discussion](https://elixirforum.com/t/convert-charlists-into-c-charlists/49455) for more context.

### Fixed

  * Numerous fixes related to vars used in guards:
    * Generated vars will no longer shadow variables in scope (e.g. if `pid` is in scope, a different pid will use the var `pid1`).
    * The same var will no longer be used for different values of the same type.
    * Multiple, redundant guards will no longer be emitted for the same var (e.g. `[self(), self()]` would result in `[pid, pid] when is_pid(pid) and is_pid(pid)`).
  * Numerous fixes related to pattern generation, especially in regards to map keys.

## v0.3.3 (2023-05-01)

### Changed

  * Improve stacktraces and ExUnit assertion errors when an auto-assertion fails or is rejected.
  * When an `auto_assert` updates, a default pattern that is more similar to the existing one will be selected in more cases when the `:default_pattern` option is set to `:infer` (the default).
  * When updating an assertion with an existing map pattern that only asserts a subset of keys, generate a pattern using that subset as well.

## v0.3.2 (2023-04-16)

### Changed

  * Multi-line string patterns will now always appear in the same order (heredoc format will always be the last option).

### Fixed

  * Raise a more comprehensible error if `Mneme.start()` is called multiple times without `restart: true`.
  * Fix an incorrect guard that could cause semantic diffing to fail and fall back to text diffing.
  * Fix multi-line string formatting issues with `auto_assert_raise`, `auto_assert_receive`, and `auto_assert_received`.

## v0.3.1 (2023-04-14)

### Changed

  * Multi-line strings will now generate both a heredoc and a single-line option.

### Removed

  * No longer depend on `libgraph`.

## v0.3.0 (2023-04-10)

It is recommended to now use Elixir v1.14.4 or later.

### Added

  * Add three new auto-assertions:
    * [`auto_assert_raise`](https://hexdocs.pm/mneme/Mneme.html#auto_assert_raise/3)
    * [`auto_assert_receive`](https://hexdocs.pm/mneme/Mneme.html#auto_assert_receive/2)
    * [`auto_assert_received`](https://hexdocs.pm/mneme/Mneme.html#auto_assert_received/1)
  * Add a `:force_update` option that forces re-generating assertion patterns even when they succeed. See the [Options documentation](https://hexdocs.pm/mneme/Mneme.html#module-options) for more info.
  * Prompts will now show options that were overridden from the defaults.
  * Mneme now prints a one-line summary at the end of the test run.

### Changed

  * For falsy values, `auto_assert` now generates `<-` pattern matches instead of `==` value comparisons, which have been removed.
  * Existing auto-assertions will now run when `Mneme.start()` is not called, but new or failing auto-assertions will fail without prompting ([#32](https://github.com/zachallaun/mneme/issues/32)).
  * Ranges now use range syntax like `1..10` and `1..10//2` instead of generating a `%Range{}` struct.

### Removed

  * **Breaking:** `auto_assert` no longer supports value comparisons using `==`.

### Fixed

  * Fix a configuration precedence bug that caused options set in application config to always override module, describe, or test options.
  * Fix a compatibility issue with Ecto ~> 3.9.4 ([#34](https://github.com/zachallaun/mneme/issues/34)).
  * Fix a confusing diff result that could occur with some binary operations ([#11](https://github.com/zachallaun/mneme/issues/11)).
  * Preceding comments are no longer shown in diffs ([#26](https://github.com/zachallaun/mneme/issues/26)).
  * Fix a number of diffing errors related to structs.

## v0.2.7 (2023-03-29)

### Fixed

  * Fix a crash related to escaped string interpolation characters ([#29](https://github.com/zachallaun/mneme/issues/29)).

## v0.2.6 (2023-03-27)

### Added

  * Auto-assertion prompts can now be skipped (`s`) in addition to accepted (`y`) or rejected (`n`). This allows the test clause to continue so that later assertions might be run, but fails the test run once the suite finishes.
  * Semantic diffs will now be displayed side-by-side if terminal width allows. To always display diffs stacked, use the `diff_style: :stacked` option; see the "Configuration" section of the `Mneme` module doc for more.

### Changed

  * Semantic diff formatting has been improved for clarity.

### Fixed

  * Don't overwrite test files if their content changes after starting the test run ([#23](https://github.com/zachallaun/mneme/issues/23)).
  * Fix a crash that occurred when a value contained nested strings with newlines, e.g. `{:ok, "hello\nworld"}` ([#25](https://github.com/zachallaun/mneme/issues/25)).
  * The `j/k` options will no longer be rendered when prompting if there is only a single pattern option.

## v0.2.4, v0.2.5 (2023-03-25)

### Fixed

  * Remove unnecessary files from Hex package. This cuts the package size down drastically.

## v0.2.3 (2023-03-25)

### Fixed

  * Fix diffing for certain sigil variations.
  * Fix `dbg`-related error when running `MIX_ENV=test iex -S mix` ([#20](https://github.com/zachallaun/mneme/issues/20)).
  * Fix ETS-related error when calling `Mneme.start/1` multiple times ([#20](https://github.com/zachallaun/mneme/issues/20#issuecomment-1483878101)).

## v0.2.2 (2023-03-20)

### Fixed

  * Disable a semantic diffing optimization that caused poor diff results in certain cases, usually manifesting as incorrect branches being compared.

## v0.2.1 (2023-03-19)

### Changed

  * More consistent formatting between `:semantic` and `:text` diffs.

## v0.2.0 (2023-03-18)

### Added

  * Adds semantic diffs which selectively highlight only meaningful changes when updating an assertion. This can be disabled with the `diff: :text` option; see the "Configuration" section of the `Mneme` module doc for more.

### Changed

  * **Breaking:** Mneme now requires Elixir v1.14 or later.

### Fixed

  * Invalid options now cause a warning instead of crashing test process.
  * Internal errors now show an error instead of crashing test process.
  * Fix bug causing multiple identical choices to be presented in some cases where empty lists were a part of the value.

## v0.1.6 (2023-03-04)

### Changed

  * Improved compile-time error message when `auto_assert` is used outside of a `test` block ([#9](https://github.com/zachallaun/mneme/issues/9)).

## v0.1.5 (2023-02-25)

### Changed

  * More consistent handling of charlists: lists of integers will now generate themselves as a pattern as well as a charlist if the list is ASCII printable ([#6](https://github.com/zachallaun/mneme/issues/6)).

## v0.1.4 (2023-02-23)

### Fixed

  * Fix a bug that could cause `auto_assert` expressions to revert to the previous value when using `Mneme.start(restart: true)` ([#7](https://github.com/zachallaun/mneme/issues/7)).

## v0.1.3 (2023-02-22)

### Added

  * Add a `:default_pattern` configuration option for auto-assertions which controls the pattern that should be selected by default when prompted.

### Fixed

  * When converting an auto-assertion to an ExUnit assertion, select the identical pattern when the `:default_pattern` is `:infer` (set by default).

## v0.1.2 (2023-02-21)

### Added

  * Add a `:restart` option to `Mneme.start/1` to restart Mneme if called multiple times.

## v0.1.1 (2023-02-20)

### Changed

  * Dramatically reduce the performance gap between `auto_assert` and ExUnit's `assert`.

## v0.1.0 (2023-02-19)

First release.
