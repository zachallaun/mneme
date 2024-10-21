ci? = System.get_env("CI") == "true"

ex_unit_config = [
  exclude: [mneme_not_started: true],
  assert_receive_timeout: if(ci?, do: 1_000, else: 100)
]

ExUnit.start(ex_unit_config)

if System.get_env("START_MNEME") != "false" do
  Mneme.start()
end
