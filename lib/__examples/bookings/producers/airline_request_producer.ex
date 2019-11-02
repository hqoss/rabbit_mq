defmodule Bookings.Producers.AirlineRequestProducer do
  alias MQ.Producer

  use Producer, exchange: "airline_request"

  @valid_airline_codes ~w(ba qr)a

  def place_booking(airline_code, %{date_time: _, flight_number: _} = params, opts \\ [])
      when airline_code in @valid_airline_codes and is_list(opts) do
    airline = airline(airline_code)
    payload = payload(params)
    opts = opts |> Keyword.put(:routing_key, "#{airline}.place_booking")

    publish(payload, opts)
  end

  def cancel_booking(airline_code, %{booking_id: _} = params, opts \\ [])
      when airline_code in @valid_airline_codes and is_list(opts) do
    airline = airline(airline_code)
    payload = payload(params)
    opts = opts |> Keyword.put(:routing_key, "#{airline}.cancel_booking")

    publish(payload, opts)
  end

  defp payload(%{date_time: _, flight_number: _} = params),
    do: params |> Map.take([:date_time, :flight_number]) |> Jason.encode!()

  defp payload(%{booking_id: _} = params),
    do: params |> Map.take([:booking_id]) |> Jason.encode!()

  defp airline(:ba), do: "british_airways"
  defp airline(:qr), do: "qatar_airways"
end
