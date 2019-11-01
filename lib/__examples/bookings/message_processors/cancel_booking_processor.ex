defmodule Bookings.MessageProcessors.CancelBookingMessageProcessor do
  require Logger

  def process_message(payload, _meta) do
    with {:ok, %{"booking_id" => booking_id}} <- Jason.decode(payload) do
      Logger.info("Attempting to cancel booking #{booking_id}.")
      :ok
    end
  end
end
