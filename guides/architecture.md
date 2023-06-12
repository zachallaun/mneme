To understand how Mneme works, we'll follow the order of execution when running `mix test`.
Afterwards, we'll dive into some specific areas of interest.

## Overview

1. `Mneme.start/1` is called first. This modifies the ExUnit configuration and starts the Mneme server, a `GenServer` that coordinates user interaction, manages IO, and stores assertion state.

2. Test modules are loaded and Mneme's macros are expanded:
    * `use Mneme` registers module attributes used for configuration, like `@mneme`.

    * `auto_assert*` macros capture their arguments and environment in `%Mneme.Assertion{}` structs and output function calls that will run with the test and do the real heavy lifting.

3. Tests begin to run. The Mneme server begins capturing all output from ExUnit, only flushing it to the console when the user is not being prompted.

4. Auto-assertions run as tests are executed. Exactly what this means depends on the type of assertion (`auto_assert`, `auto_assert_raise`, etc.) and whether it is a new assertion with no reference value or not. The basic order of operations is:
    * Capture the value being asserted and compare it against the reference value, if present. If it succeeds, carry on.

    * If the assertion fails or there wasn't a reference value to begin with, a call is made to the Mneme server to update it.

    * A set of patterns are constructed and presented to the user in diffs.

    * The user either selects a pattern or rejects them. If selected, the update is stored for later and the test continues. If rejected, the test fails.

5. Once all tests complete, the Mneme server updates the test files for any patched assertions and prints a summary.

## Generating assertions

TODO

## Server responsibilities

TODO

## Terminal UI

TODO

## Diffing

TODO
