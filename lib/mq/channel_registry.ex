defmodule MQ.ChannelRegistry do
  alias AMQP.Channel

  require Logger

  @registry :mq_channel_registry

  # @max_channel_count 64

  @spec init() :: :ok
  def init do
    _ = :ets.new(@registry, [:set, :protected, :named_table, read_concurrency: true])
    :ok
  end

  @spec lookup(atom()) :: {:ok, Channel.t()} | {:error, :channel_not_found}
  def lookup(server_name) when is_atom(server_name) do
    case :ets.lookup(@registry, server_name) do
      # We use `insert_new` so this will always match
      [{^server_name, %Channel{} = channel}] -> {:ok, channel}
      [] -> {:error, :channel_not_found}
    end
  end

  @spec insert(atom(), Channel.t()) :: :ok
  def insert(server_name, channel) do
    case :ets.insert_new(@registry, {server_name, channel}) do
      true ->
        :ok

      _ ->
        Logger.warn("Channel already exists for #{server_name}, skipping insert.")
        :ok
    end
  end

  @spec delete(atom()) :: :ok
  def delete(server_name) do
    _ = :ets.delete(@registry, server_name)
    :ok
  end
end
