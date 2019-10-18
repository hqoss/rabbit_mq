defmodule MQ.AMQPConfig do
  def config do
    :rabbitex
    |> Application.get_env(:config, [])
  end

  def url do
    config() |> Keyword.fetch!(:amqp_url)
  end

  def exchanges do
    config() |> Keyword.fetch!(:exchanges)
  end
end
