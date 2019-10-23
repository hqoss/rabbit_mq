defmodule MQ.Support.RabbitCase do
  @moduledoc """
  Used to setup tests using RabbitMQ and ensure exclusivity.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias MQ.ConnectionManager
      alias MQ.Topology.Queue

      @this_module __MODULE__
      @channel_holder :test_process_channel_holder

      setup_all do
        assert {:ok, _pid} = start_supervised(ConnectionManager)
        assert {:ok, channel} = ConnectionManager.request_channel(@this_module)

        [channel: channel]
      end

      setup %{channel: channel} do
        Queue.purge_all(channel)
      end
    end
  end
end
