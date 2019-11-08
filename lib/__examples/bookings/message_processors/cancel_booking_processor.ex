defmodule Bookings.MessageProcessors.CancelBookingMessageProcessor do
  alias Bookings.Store

  require Logger

  @type error() :: :invalid_payload | Jason.DecodeError | :not_found

  @doc """
  Processes `*.cancel_booking` messages from the `airline_request` exchange.
  Calls a 3rd party API to cancel a booking, removes the booking from `Bookings.Store`.
  """
  @spec process_message(String.t(), map()) :: :ok | {:error, error()}
  def process_message(payload_binary, _meta) do
    with {:ok, payload} <- parse_message(payload_binary),
         {:ok, booking} <- Store.get_existing(payload.booking_id) do
      %{id: booking_id, external_booking_id: external_booking_id} = booking

      Logger.info("Attempting to cancel #{booking_id}, external id: #{external_booking_id}.")

      # Fake HTTP call to a 3rd party to cancel the booking, using `external_booking_id`,
      # for example: `AirlineClient.cancel_booking(external_booking_id)`.

      :ok = Store.delete(booking_id)

      Logger.info("Booking #{booking_id} successfully cancelled.")

      :ok
    end
  end

  defp parse_message(payload_binary) do
    case Jason.decode(payload_binary) do
      {:ok, %{"booking_id" => booking_id}} ->
        {:ok, %{booking_id: booking_id}}

      {:ok, _} ->
        {:error, :invalid_payload}

      error ->
        error
    end
  end
end
