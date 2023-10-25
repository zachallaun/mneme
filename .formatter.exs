locals_without_parens = [
  auto_assert: :*,
  auto_assert_raise: :*,
  auto_assert_receive: :*,
  auto_assert_received: :*
]

[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib}/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "test_integration/**/*.{ex,exs}",
    "examples/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens],
  import_deps: [:stream_data],
  plugins: [Styler],
  line_length: 98
]
