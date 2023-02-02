# Notes

## TODO

- [ ] Shouldn't prompt and should auto-fail if `CI` env var is set.
- [ ] Abstract the prompt provider (e.g. Terminal) so that it can also do things like prompt inside VSCode once there's an extension.
- [ ] Figure out how to hook into ExUnit tags so that you can do things like:
  - [ ] Replace `auto_assert` with a basic `assert` match, in case people want to "uninstall" Mneme.
  - [ ] Don't use `^pin` even if the value is found in the current scope.

## VSCode integration

Would be awesome to have a VSCode extension where you could run a command and it would give you a diff thingy in the editor that you could accept/reject.
