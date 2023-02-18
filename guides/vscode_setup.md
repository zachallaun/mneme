# VS Code Setup

If you are using Visual Studio Code and the [ElixirLS](https://github.com/elixir-lsp/vscode-elixir-ls) extension, there are a couple of things that you can do to smooth out the workflow of running and updating your tests.

The ElixirLS extension comes with some built-in tasks to run tests:

  * `mix: Run tests`
  * `mix: Run tests in current file`
  * `mix: Run test at cursor`

These are accessible by running the command `Run task` and then typing typing one of the tasks.
By default, these will open a terminal panel, but will not focus it, which isn't optimal as Mneme requires input when something changes.

We can bind these tasks to a keyboard shortcut globally and then update the focus defaults on a per-project basis.

## Keyboard shortcuts

Run the command `Preferences: Open Keyboard Shortcuts (JSON)`, then copy the following keyboard shortcuts to the bottom of the list:

```json
{
  "key": "ctrl+space a",
  "command": "workbench.action.tasks.runTask",
  "args": "mix: Run tests"
},
{
  "key": "ctrl+space f",
  "command": "workbench.action.tasks.runTask",
  "args": "mix: Run tests in current file"
},
{
  "key": "ctrl+space c",
  "command": "workbench.action.tasks.runTask",
  "args": "mix: Run test at cursor"
},
```

You can replace `"key"` with whatever you'd prefer.

## Per-project task defaults

Tasks provided by extensions can be modified by adding a `.vscode/tasks.json` to your project's root.
The following will modify the tasks listed above to give input focus to the panel they're run in.

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "group": "test",
      "type": "mix",
      "task": "Run tests",
      "presentation": {
        "focus": true,
      },
    },
    {
      "group": "test",
      "type": "mix",
      "task": "Run tests in current file",
      "presentation": {
        "focus": true,
      },
    },
    {
      "group": "test",
      "type": "mix",
      "task": "Run test at cursor",
      "presentation": {
        "focus": true,
      },
    },
  ],
}
```

The Mneme repository has this set up [here](https://github.com/zachallaun/mneme/blob/main/.vscode/tasks.json), for example.
