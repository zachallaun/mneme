# Changelog

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.1.6 (2023-03-04)

### Enhancements

  * Improved compile-time error message when `auto_assert` is used outside of a `test` block ([#9](https://github.com/zachallaun/mneme/issues/9)).

## v0.1.5 (2023-02-25)

### Enhancements

  * More consistent handling of charlists: lists of integers will now generate themselves as a pattern as well as a charlist if the list is ASCII printable ([#6](https://github.com/zachallaun/mneme/issues/6)).

## v0.1.4 (2023-02-23)

### Fixes

  * Fix a bug that could cause `auto_assert` expressions to revert to the previous value when using `Mneme.start(restart: true)` ([#7](https://github.com/zachallaun/mneme/issues/7)).

## v0.1.3 (2023-02-22)

### Enhancements

  * Add a `:default_pattern` configuration option for auto-assertions which controls the pattern that should be selected by default when prompted.

### Fixes

  * When converting an auto-assertion to an ExUnit assertion, select the identical pattern when the `:default_pattern` is `:infer` (set by default).

## v0.1.2 (2023-02-21)

### Enhancements

  * Add a `:restart` option to `Mneme.start/1` to restart Mneme if called multiple times.

## v0.1.1 (2023-02-20)

### Enhancements

  * Dramatically reduce the performance gap between `auto_assert` and ExUnit's `assert`.

## v0.1.0 (2023-02-19)

First release.
