# Mneme Examples

This directory contains examples and demos of Mneme usage.

## Tour Mneme

`tour_mneme.exs` is meant to be a standalone tour of Mneme's features that can be run by simply downloading the script and running `elixir tour_mneme.exs`.
It uses `Mix.install/1` to install the latest version of Mneme and run an example test module demonstrating Mneme's usage.

## Recording demos

Demo GIFs/videos are recorded using [VHS](https://github.com/charmbracelet/vhs).
Version 0.3.1 is currently required, which as of this writing, is still in development.
VHS relies on [ttyd](https://github.com/tsl0922/ttyd) and [ffmpeg](https://ffmpeg.org/) being installed and available on your `PATH`.

To install the main branch of VHS:

```sh
$ go install github.com/charmbracelet/vhs@main
```

Demos can be re-recorded from the root of this project by running:

```sh
$ vhs < examples/demo.tape
# will output examples/demo.gif, examples/demo.mp4, etc.
```
