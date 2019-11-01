defmodule Bookings.MessageProcessors.PlaceBookingMessageProcessor do
  require Logger

  @date_format "{WDfull}, {0D} {Mfull} {YYYY}"

  def process_message(payload, _meta) do
    with {:ok, %{"date_time" => date_time_iso, "flight_number" => flight_number}} <-
           Jason.decode(payload),
         {:ok, date_time, _} <- DateTime.from_iso8601(date_time_iso),
         {:ok, formatted_date} <- Timex.format(date_time, @date_format) do
      Logger.info("Attempting to book #{flight_number} for #{formatted_date}.")
      :ok
    end
  end
end
