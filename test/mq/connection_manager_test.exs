defmodule MQTest.ConnectionManager do
  alias AMQP.{Channel, Connection}
  alias MQ.ChannelRegistry
  alias MQ.ConnectionManager

  use ExUnit.Case

  # doctest MQ.ConnectionManager

  describe "MQ.ConnectionManager" do
    defp unique_module_name do
      :crypto.strong_rand_bytes(8) |> Base.encode64() |> String.to_atom()
    end

    test "connects to AMQP and has the ability to retrieve normal and confirm channels on the same connection" do
      assert {:ok, _pid} = start_supervised(ConnectionManager)

      assert {:ok, %Channel{} = channel} = ConnectionManager.request_channel(unique_module_name())

      assert {:ok, %Channel{} = confirm_channel} =
               ConnectionManager.request_confirm_channel(unique_module_name())

      assert channel.conn == confirm_channel.conn
    end

    test "opens a new channel per module/name and saves it in the registry" do
      assert {:ok, _pid} = start_supervised(ConnectionManager)

      module_a = unique_module_name()
      module_b = unique_module_name()

      assert {:ok, channel_a} = ConnectionManager.request_channel(module_a)
      assert {:ok, channel_b} = ConnectionManager.request_channel(module_b)

      assert channel_a !== channel_b

      assert {:ok, cached_channel_a} = ChannelRegistry.lookup(module_a)
      assert {:ok, cached_channel_b} = ChannelRegistry.lookup(module_b)

      assert channel_a == cached_channel_a
      assert channel_b == cached_channel_b
    end

    test "sends a clean :EXIT signal when the connection process dies" do
      assert {:ok, pid} = ConnectionManager.start_link([])

      # Makes it possible to receive messages in the test process's mailbox.
      Process.flag(:trap_exit, true)

      assert {:ok, %Channel{conn: %Connection{pid: connection_pid}}} =
               ConnectionManager.request_channel(:test_module)

      Process.exit(connection_pid, :connection_down)

      assert_receive {:EXIT, ^pid, {:connection_lost, _reason}}
    end
  end
end
