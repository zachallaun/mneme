defmodule Mneme.Integration.ReceiveTest do
  use ExUnit.Case
  use Mneme

  describe "auto_assert_receive" do
    test "consumes messages from inbox" do
      send(self(), {:one, :message})

      # y
      auto_assert_receive {:one, :message}

      assert {:messages, []} = Process.info(self(), :messages)
    end

    test "consumes messages sent within 100ms" do
      Process.send_after(self(), {:one, :message}, 30)

      # y
      auto_assert_receive {:one, :message}

      assert {:messages, []} = Process.info(self(), :messages)
    end

    test "shows all messages received as possible patterns" do
      send(self(), {:message, 1})
      send(self(), {:message, 2})
      send(self(), {:message, 3})

      # y
      auto_assert_receive {:message, 1}

      # y
      auto_assert_receive {:message, 2}

      # y
      auto_assert_receive {:message, 3}
    end

    test "supports guards" do
      send(self(), {:message, self()})

      # y
      auto_assert_receive {:message, pid} when is_pid(pid)
    end

    test "raises if no messages arrive within timeout" do
      assert_raise Mneme.AssertionError, fn ->
        auto_assert_receive()
      end
    end
  end

  describe "auto_assert_received" do
    test "consumes messages from inbox" do
      send(self(), {:one, :message})

      # y
      auto_assert_received {:one, :message}

      assert {:messages, []} = Process.info(self(), :messages)
    end

    test "raises if no messages are immediately available" do
      Process.send_after(self(), {:one, :message}, 10)

      assert_raise Mneme.AssertionError, fn ->
        # ignore
        auto_assert_received {:one, :message}
      end
    end

    test "shows all messages received as possible patterns" do
      send(self(), {:message, 1})
      send(self(), {:message, 2})
      send(self(), {:message, 3})

      # y
      auto_assert_received {:message, 1}

      # y
      auto_assert_received {:message, 2}

      # y
      auto_assert_received {:message, 3}
    end

    test "supports guards" do
      send(self(), {:message, self()})

      # y
      auto_assert_received {:message, pid} when is_pid(pid)
    end
  end
end
