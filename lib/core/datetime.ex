defmodule Core.DateTime do
  @moduledoc """
  Contains DateTime convenience methods.
  """

  @doc """
  Returns current time as a unix timestamp.
  The time unit is `:millisecond` by default.
  """
  @spec now_unix(unit :: System.time_unit()) :: integer()
  def now_unix(unit \\ :millisecond) do
    DateTime.utc_now() |> DateTime.to_unix(unit)
  end
end
