defmodule MQ.AMQPConfig do
  def config do
    :rabbit_mq_ex
    |> Application.get_env(:config, [])
  end

  def url, do: config() |> Keyword.fetch!(:amqp_url)

  def topology, do: config() |> Keyword.fetch!(:topology)
end
