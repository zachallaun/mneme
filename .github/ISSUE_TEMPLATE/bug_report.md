---
name: Bug report
about: Create a report to help us improve
title: ''
labels: bug
assignees: ''

---

Elixir version:
Erlang/OTP version:
Mneme version:

## Description

A clear and concise description of the bug and your expected behavior.

## To reproduce

Steps and code needed to reproduce the issue.

```elixir
Mix.install([
  # use exact versions from your mix.lock
  {:mneme, "0.6.0"},
  ...
])

ExUnit.start()
Mneme.start()

defmodule Repro do
  use ExUnit.Case
  use Mneme

  test "reproduction" do
    auto_assert ...
  end
end

ExUnit.run()
```

## Additional context

Add any other context about the problem here.
