defmodule MQ.Topology.Queue do
  alias AMQP.{
    Channel,
    Connection,
    Queue
  }

  @amqp_url "amqp://guest:guest@localhost:5672"

  def purge_all(topology) when is_list(topology) do
    with queues <- get_queues(topology),
         {:ok, connection} <- Connection.open(@amqp_url),
         {:ok, channel} <- Channel.open(connection),
         results <- channel |> purge_all(queues),
         :ok <- channel |> Channel.close() do
      {:ok, results}
    end
  end

  defp purge_all(channel, queues) do
    queues |> Enum.map(&Queue.purge(channel, &1)) |> IO.inspect()
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
