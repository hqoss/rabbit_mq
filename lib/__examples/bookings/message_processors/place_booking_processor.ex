defmodule Bookings.MessageProcessors.PlaceBookingMessageProcessor do
  alias Bookings.Store

  import Bookings.Core.DateTimeFormatter, only: [format_iso_date_time: 2]

  require Logger

  @date_format "{WDfull}, {0D} {Mfull} {YYYY}"

  @type error() :: :invalid_payload | Jason.DecodeError | :invalid_format

  @doc """
  Processes `*.place_booking` messages from the `airline_request` exchange.
  Calls a 3rd party API to place a booking, saves the booking into `Bookings.Store`.
  """
  @spec process_message(String.t(), map()) :: :ok | {:error, error()}
  def process_message(payload_binary, _meta) do
    with {:ok, payload} <- parse_message(payload_binary),
         {:ok, formatted_date} <- format_iso_date_time(payload.date_time, @date_format) do
      Logger.info("Attempting to book #{payload.flight_number} for #{formatted_date}.")

      # Fake HTTP call to a 3rd party, receive `external_booking_id`,
      # for example: `AirlineClient.place_booking(payload)`.
      external_booking_id = UUID.uuid4()

      attrs = Map.merge(payload, %{external_booking_id: external_booking_id})

      # Not matching this would result in an exception which will fall
      # back to `{:error, :retry_once}`, so we let it fail.
      {:ok, booking} = Store.insert(attrs)

      Logger.info("Successfully booked #{inspect(booking)}.")

      :ok
    end
  end

  defp parse_message(payload_binary) do
    case Jason.decode(payload_binary) do
      {:ok, %{"date_time" => date_time, "flight_number" => flight_number}} ->
        {:ok, %{date_time: date_time, flight_number: flight_number}}

      {:ok, _} ->
        {:error, :invalid_payload}

      error ->
        error
    end
  end
end
