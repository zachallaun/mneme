# Mneme /ni:mi:/

Mneme helps you write tests.

Inspired by [Jane Street's expect-test](https://github.com/janestreet/ppx_expect), which you can [read about here](https://blog.janestreet.com/the-joy-of-expect-tests/).

Prior art: [assert_value](https://github.com/assert-value/assert_value_elixir)

## Installation

**MNEME IS NOT READY FOR GENERAL USE!**
If you're finding it published on Hex, it's only so that I can be my own guinea pig and use it while working on other libraries.

If available in Hex, the package can be installed by adding `mneme` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mneme, ">= 0.0.0"}
  ]
end
```

## VSCode Integration

For happier times in VSCode, set up ElixirLS, copy the `.vscode/tasks.json` from this repository to your workspace, and then add the following keybindings:

```json
[
  {
    "key": "ctrl+; a",
    "command": "workbench.action.tasks.runTask",
    "args": "mix: Run tests"
  },
  {
    "key": "ctrl+; f",
    "command": "workbench.action.tasks.runTask",
    "args": "mix: Run tests in current file"
  },
  {
    "key": "ctrl+; c",
    "command": "workbench.action.tasks.runTask",
    "args": "mix: Run test at cursor"
  },
]
```

