defmodule Examples.Producers.LogProducer do
  use MQ.Producer, exchange: "log"

  @valid_types ~w(debug, info, warn, error)a

  def publish_logs(type \\ :info, count \\ 10_000)
      when type in @valid_types
      when is_integer(count) do
    1..count
    |> Stream.map(&payload(type, &1))
    |> Task.async_stream(&do_publish/1)
    |> Stream.each(&log_publish_result/1)
    |> Stream.run()
  end

  defp payload(type, index) when is_integer(index),
    do: {type, "Log message (#{index}) type: #{type}."}

  defp do_publish({type, payload}) do
    routing_key = type |> routing_key()
    Logger.metadata(payload: payload, routing_key: routing_key)
    publish(payload, routing_key: routing_key)
  end

  defp log_publish_result({:ok, :ok}),
    do: Logger.info("Event successfully published")

  defp log_publish_result(result),
    do: Logger.error("Failed to publish event, result: #{inspect(result)}")

  defp routing_key(:debug), do: "log.debug"
  defp routing_key(:info), do: "log.info"
  defp routing_key(:warn), do: "log.warn"
  defp routing_key(:error), do: "log.error"
end
