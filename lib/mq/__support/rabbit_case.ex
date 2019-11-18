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
        assert {:ok, _pid} = start_connection_manager()
        assert {:ok, channel} = ConnectionManager.request_channel(@this_module)

        [channel: channel]
      end

      setup %{channel: channel} do
        Queue.purge_all(channel)
      end

      defp start_connection_manager do
        with pid when is_pid(pid) <- Process.whereis(ConnectionManager),
             true <- Process.alive?(pid) do
          {:ok, pid}
        else
          _ -> start_supervised(ConnectionManager)
        end
      end
    end
  end
end
