defmodule MQTest.Support.TestConsumerRegistry do
  require Logger

  @registry :mq_support_test_consumer_registry

  @spec init() :: :ok
  def init do
    _ = :ets.new(@registry, [:set, :public, :named_table, read_concurrency: true])
    :ok
  end

  @spec lookup_pid(String.t()) :: {:ok, pid()} | {:error, :pid_not_found}
  def lookup_pid(consumer_tag) when is_binary(consumer_tag) do
    case :ets.lookup(@registry, consumer_tag) do
      # We use `insert_new` so this will always match
      [{^consumer_tag, pid}] -> {:ok, pid}
      [] -> {:error, :pid_not_found}
    end
  end

  @spec register_pid(String.t(), pid()) :: :ok
  def register_pid(reply_to, pid) when is_binary(reply_to) and is_pid(pid) do
    case :ets.insert_new(@registry, {reply_to, pid}) do
      true ->
        :ok

      _ ->
        Logger.warn("Entry for #{reply_to} already exists, skipping insert.")
        :ok
    end
  end

  # @spec delete_entry(String.t()) :: :ok
  # defp delete_entry(consumer_tag) do
  #   _ = :ets.delete(@registry, consumer_tag)
  #   :ok
  # end
end
