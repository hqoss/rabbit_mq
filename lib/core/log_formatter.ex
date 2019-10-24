defmodule Core.LogFormatter do
  @moduledoc """
  Useful log formatter, outputs JSON in `prod`.
  """

  @doc false
  def format(level, message, {date, {hh, mm, ss, _ms}} = timestamp, metadata) do
    iso_timestamp =
      {date, {hh, mm, ss}}
      |> NaiveDateTime.from_erl!()
      |> DateTime.from_naive!("Etc/UTC")

    meta =
      metadata
      |> Enum.into(%{})
      |> Map.put(:timestamp, iso_timestamp)
      |> Map.drop([:pid, :module, :function])

    [
      "\n",
      "[#{level}] #{message}",
      "METADATA: #{Jason.encode!(meta, pretty: true)}"
    ]
    |> Enum.join("\n")
  rescue
    exception ->
      [
        "\n",
        "Could not format message: #{inspect({level, message, timestamp, metadata})}.",
        "Error: #{inspect(exception)}."
      ]
      |> Enum.join("\n")
  end
end
