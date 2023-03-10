# Used by "mix format"
locals_without_parens = [auto_assert: 1, auto_assert: 2]

[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib}/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "test_integration/**/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
