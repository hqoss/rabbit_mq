defmodule MQTest.ConnectionManager do
  alias MQ.ConnectionManager

  use ExUnit.Case

  @this_module __MODULE__

  # doctest MQ.ConnectionManager

  describe "MQ.ConnectionManager" do
    @tag :wip
    test "connects to AMQP given a URL" do
      {:ok, _pid} = start_supervised(ConnectionManager)
      assert {:ok, _channel} = ConnectionManager.request_channel(@this_module)
    end
  end
end
