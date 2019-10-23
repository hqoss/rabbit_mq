defmodule Core.DateTime do
  @spec now_unix(unit :: System.time_unit()) :: integer()
  def now_unix(unit \\ :millisecond) do
    DateTime.utc_now() |> DateTime.to_unix(unit)
  end
end
