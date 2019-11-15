defmodule MQ.AMQPConfig do
  @moduledoc """
  Retrieves `rabbit_mq_ex` config values.
  """

  @type exchange() :: {String.t(), keyword()}

  @doc """
  Gets the `amqp_url` defined in config under `rabbit_mq_ex`.
  """
  @spec url() :: String.t()
  def url, do: config(:amqp_url)

  @doc """
  Gets the `topology` defined in config under `rabbit_mq_ex`.
  """
  @spec topology() :: list(exchange())
  def topology, do: config(:topology)

  defp config(key) do
    :rabbit_mq_ex
    |> Application.get_env(key)
  end
end
