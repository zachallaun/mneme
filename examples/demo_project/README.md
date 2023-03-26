# Mneme Demo Project

This project is used to record demos for Mneme.

Demos are recorded using [VHS](https://github.com/charmbracelet/vhs).

```shell
$ vhs < examples/demo.tape
```

To prevent demos from actually updating the tests, this project uses a currently private application config option: `config :mneme, dry_run: true`.
