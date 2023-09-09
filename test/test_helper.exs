ExUnit.start(exclude: [mneme_not_started: true])

if System.get_env("START_MNEME") != "false" do
  Mneme.start()
end
