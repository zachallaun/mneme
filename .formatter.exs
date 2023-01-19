# Used by "mix format"
locals_without_parens = [auto_assert: 1]

[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib}/**/*.{ex,exs}",
    "test/*.exs",
    "test/{support,mneme}/**/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
