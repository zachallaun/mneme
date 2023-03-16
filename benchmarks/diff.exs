# mix run benchmarks/diff.exs
#
# The first run will save benchmark results to a file and subsequent
# results will compare to that file.
#
# Set env var `BENCHEE_SAVE=true` to overwrite the saved results.
# Set env var `BENCHEE_PROFILE=true` to run profiler.

save_file = Path.expand("diff.benchee", __DIR__)

inputs = [
  simple: {
    "auto_assert Function.identity(self())",
    "auto_assert pid when is_pid(pid) <- Function.identity(self())"
  },
  moderate: {
    """
    auto_assert {[["[:foo, ", %Tag{data: ":bar", sequences: [:red]}, ", :baz]"]],
                  [["[", %Tag{data: ":bar", sequences: [:green]}, ", :foo, :baz]"]]} <-
                  format("[:FOO, :BAR, [:BAZ]]", "[:BAR, :FOO, [:BAZ]]")
    """,
    """
    auto_assert {[["[:FOO, ", %Tag{data: ":BAR", sequences: [:red]}, ", [:BAZ]]"]],
                  [["[", %Tag{data: ":BAR", sequences: [:green]}, ", :FOO, :BAZ]"]]} <-
                  format("[:FOO, :BAR, [:BAZ]]", "[:BAR, :FOO, [:BAZ]]")
    """
  },
  complex: {
    """
    auto_assert {:<<>>, [closing: [line: 1, column: 40], line: 1, column: 1],
                  [
                    {:int, [token: "0", line: 1, column: 3], 0},
                    {:"::", [line: 1, column: 10],
                    [
                      {:var, [line: 1, column: 6], :head},
                      {:-, [line: 1, column: 18],
                        [
                          {:var, [line: 1, column: 12], :binary},
                          {:size, [closing: [line: 1, column: 25], line: 1, column: 19],
                          [{:int, [token: "4", line: 1, column: 24], 4}]}
                        ]}
                    ]},
                    {:"::", [line: 1, column: 32],
                    [
                      {:var, [line: 1, column: 28], :rest},
                      {:var, [line: 1, column: 34], :binary}
                    ]}
                  ]} <- parse_string!("<<1, h::binary-size(2), more::binary>>")
    """,
    """
    auto_assert {:<<>>, [closing: [line: 1, column: 37], line: 1, column: 1],
                  [
                    {:int, [token: "1", line: 1, column: 3], 1},
                    {:"::", [line: 1, column: 7],
                    [
                      {:var, [line: 1, column: 6], :h},
                      {:-, [line: 1, column: 15],
                        [
                          {:var, [line: 1, column: 9], :binary},
                          {:size, [closing: [line: 1, column: 22], line: 1, column: 16],
                          [{:int, [token: "2", line: 1, column: 21], 2}]}
                        ]}
                    ]},
                    {:"::", [line: 1, column: 29],
                    [
                      {:var, [line: 1, column: 25], :more},
                      {:var, [line: 1, column: 31], :binary}
                    ]}
                  ]} <- parse_string!("<<1, h::binary-size(2), more::binary>>")
    """
  }
]

profile? = System.get_env("BENCHEE_PROFILE") == "true"
save? = !File.exists?(save_file) || System.get_env("BENCHEE_SAVE") == "true"

opts =
  cond do
    profile? -> [profile_after: true]
    save? -> [save: [path: save_file, tag: "baseline"]]
    true -> [load: save_file]
  end

Benchee.run(
  %{"Mneme.Diff.format/2" => fn {l, r} -> Mneme.Diff.format(l, r) end},
  opts ++ [
    inputs: inputs,
    warmup: 1,
    time: 3,
    memory_time: 1
  ]
)
