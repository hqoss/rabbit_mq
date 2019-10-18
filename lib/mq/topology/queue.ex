defmodule MQ.Topology.Queue do
  alias AMQP.{
    Channel,
    Queue
  }

  alias MQ.Topology.Config

  @spec purge_all(Channel.t()) :: {:ok, list()}
  def purge_all(channel) do
    queues = Config.gen() |> get_queues()
    results = purge_all(channel, queues)

    {:ok, results}
  end

  defp purge_all(channel, queues) do
    queues |> Enum.map(&Queue.purge(channel, &1))
  end

  defp get_queues(topology) do
    topology
    |> Stream.flat_map(& &1.queues)
    |> Stream.flat_map(fn {dlq, queue} -> [dlq, queue] end)
    |> Stream.map(& &1.name)
    |> Stream.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
