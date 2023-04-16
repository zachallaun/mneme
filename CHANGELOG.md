# Changelog

This format is based on [Keep a Changelog](https://keepachangelog.com) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

  * Raise a more comprehensible error if `Mneme.start()` is called multiple times without `restart: true`.
  * Fix an incorrect guard that could cause semantic diffing to fail and fall back to text diffing.

## v0.3.1 (2023-04-14)

### Changed

  * Pattern generation improvements:
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
  * Pattern generation improvements:
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
