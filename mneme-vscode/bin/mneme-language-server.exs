#!/usr/bin/env elixir

System.no_halt(true)

mneme_ls_path = Path.expand("../../mneme_ls", __DIR__)

Mix.install([
  {:mneme_ls, path: mneme_ls_path}
])

Application.ensure_all_started(:mneme_ls)
