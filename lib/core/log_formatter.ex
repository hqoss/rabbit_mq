defmodule Core.LogFormatter do
  @moduledoc """
  Useful log formatter, should output JSON in prod environment.
  """

  @doc false
  def format(level, message, {date, {hh, mm, ss, ms}} = timestamp, metadata) do
    iso_timestamp =
      {date, {hh, mm, ss}}
      |> NaiveDateTime.from_erl!(ms)
      |> DateTime.from_naive!("Etc/UTC")

    meta =
      metadata
      |> Enum.map(&format/1)
      |> Enum.into(%{})
      |> Map.put(:timestamp, iso_timestamp)

    # |> Map.drop([:domain, :mfa, :gl, :mfargs, :time, :error_logger, :report_cb])

    case Application.get_env(:rabbit_mq_ex, :env) do
      :dev ->
        Jason.encode!(meta)

      _ ->
        [
          "\n",
          "[#{level}] #{message}",
          "METADATA: #{Jason.encode!(meta, pretty: true)}"
        ]
        |> Enum.join("\n")
    end
  rescue
    exception ->
      [
        "\n",
        "Could not format message: #{inspect({level, message, timestamp, metadata})}.",
        "Error: #{inspect(exception)}."
      ]
      |> Enum.join("\n")
  end

  def format({key, value}) when is_pid(value) or is_tuple(value), do: {key, "#{inspect(value)}"}
  def format(skip), do: skip
end
