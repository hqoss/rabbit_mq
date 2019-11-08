defmodule Bookings.Core.DateTimeFormatter do
  @spec format_iso_date_time(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, error :: :invalid_format}
  def format_iso_date_time(iso_date_time, format) do
    with {:ok, date_time, _} <- DateTime.from_iso8601(iso_date_time) do
      Timex.format(date_time, format)
    end
  end
end
