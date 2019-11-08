defmodule Bookings.Producers.AirlineRequestProducer do
  use MQ.Producer, exchange: "airline_request"

  @valid_airlines ~w(british_airways qatar_airways)a

  @spec place_booking(String.t(), map()) :: :ok
  def place_booking(airline, %{date_time: _, flight_number: _} = params, opts \\ [])
      when airline in @valid_airlines and is_list(opts) do
    payload = params |> Map.take([:date_time, :flight_number]) |> Jason.encode!()
    opts = opts |> Keyword.put(:routing_key, "#{airline}.place_booking")
    publish(payload, opts)
  end

  @spec cancel_booking(String.t(), map()) :: :ok
  def cancel_booking(airline, %{booking_id: _} = params, opts \\ [])
      when airline in @valid_airlines and is_list(opts) do
    payload = params |> Map.take([:booking_id]) |> Jason.encode!()
    opts = opts |> Keyword.put(:routing_key, "#{airline}.cancel_booking")
    publish(payload, opts)
  end
end
