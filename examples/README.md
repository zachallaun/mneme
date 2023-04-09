# Mneme Examples

This folder contains examples and demos of Mneme usage.

## Tour Mneme

`tour_mneme.exs` is meant to be a standalone tour of Mneme's features that can be run by simply downloading the script and running `elixir tour_mneme.exs`.
It uses `Mix.install/1` to install the latest version of Mneme and run an example test module demonstrating Mneme's usage.

## Recording demos

Demos are recorded using [VHS](https://github.com/charmbracelet/vhs) (>= 0.4.0).
VHS relies on [ttyd](https://github.com/tsl0922/ttyd) and [ffmpeg](https://ffmpeg.org/) being installed and available on your `PATH`.

To install:

```sh
$ go install github.com/charmbracelet/vhs@latest
```

Demos can be re-recorded from the root of this project by running:

```sh
$ vhs < examples/demo.tape
# updates examples/demo.gif and examples/demo.mp4
```
