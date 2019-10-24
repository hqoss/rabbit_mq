defmodule MQTest.Support.Producers.ServiceRequestProducer do
  use MQ.Producer, exchange: "service_request"

  def place_booking(booking_data, opts) when is_list(opts) do
    payload = payload(booking_data)
    opts = opts |> Keyword.put(:routing_key, "place_booking")

    publish(payload, opts)
  end

  def cancel_booking(booking_id, opts) when is_binary(booking_id) and is_list(opts) do
    payload = payload(booking_id)
    opts = opts |> Keyword.put(:routing_key, "cancel_booking")

    publish(payload, opts)
  end

  defp payload(%{user_id: _, checkout_reference: _} = booking_data),
    do: booking_data |> Map.take([:user_id, :checkout_reference]) |> Jason.encode!()

  defp payload(booking_id), do: %{booking_id: booking_id} |> Jason.encode!()

  # def publish_logs(type \\ :info, count \\ 10_000)
  #     when type in @valid_types
  #     when is_integer(count) do
  #   1..count
  #   |> Stream.map(&payload(type, &1))
  #   |> Task.async_stream(&do_publish/1)
  #   |> Stream.each(&log_publish_result/1)
  #   |> Stream.run()
  # end

  # defp payload(type, index) when is_integer(index),
  #   do: {type, "Log message (#{index}) type: #{type}."}

  # defp do_publish({type, payload}) do
  #   routing_key = type |> routing_key()
  #   Logger.metadata(payload: payload, routing_key: routing_key)
  #   publish(payload, routing_key: routing_key)
  # end

  # defp log_publish_result({:ok, :ok}),
  #   do: Logger.info("Event successfully published")

  # defp log_publish_result(result),
  #   do: Logger.error("Failed to publish event, result: #{inspect(result)}")

  # defp routing_key(:debug), do: "log.debug"
  # defp routing_key(:info), do: "log.info"
  # defp routing_key(:warn), do: "log.warn"
  # defp routing_key(:error), do: "log.error"
end
