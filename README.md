![Elixir CI](https://github.com/hqoss/rabbit_mq/workflows/Elixir%20CI/badge.svg)
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/d8c50db737fe4b9bae614e2d06710443)](https://www.codacy.com/gh/hqoss/rabbit_mq?utm_source=github.com&utm_medium=referral&utm_content=hqoss/rabbit_mq&utm_campaign=Badge_Grade)

# 🐇 Elixir RabbitMQ Client

`rabbit_mq` is an opinionated RabbitMQ client to help _you_ build balanced and consistent Consumers and Producers.

## Table of contents

-   [Installation and Usage](#installation-and-usage)
-   [Documentation](#documentation)
-   [Configuration](#configuration)
-   [Balanced performance and reliability](#balanced-performance-and-reliability)
-   [Consistency](#consistency)
-   [TODO](#todo)

## Installation and Usage

Add `:rabbit_mq` as a dependency to your project's `mix.exs`:

```elixir
defp deps do
  [
    {:rabbit_mq, "~> 0.0.0-alpha-8"}
  ]
end
```

## Documentation

The full documentation is [published on hex](https://hexdocs.pm/rabbit_mq/).

The following modules are provided;

-   [`RabbitMQ.Topology`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Topology.html)
-   [`RabbitMQ.Consumer`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Consumer.html)
-   [`RabbitMQ.Producer`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Producer.html)

## Configuration

The following can be configured.

```elixir
config :rabbit_mq,
  amqp_url: "amqp://guest:guest@localhost:5672",
  heartbeat_interval_sec: 60,
  reconnect_interval_ms: 2500,
  max_channels_per_connection: 16
```

-   `amqp_url`; **required**, the broker URL.
-   `heartbeat_interval_sec`; defines after what period of time the peer TCP connection should be considered unreachable. Defaults to `30`.
-   `reconnect_interval_ms`; the interval before another attempt to re-connect to the broker should occur. Defaults to `2500`.
-   `max_channels_per_connection`; maximum number of channels per connection. Also determines the maximum number of workers per Producer/Consumer module. Defaults to `8`.

⚠️ Please consult the [Channels Resource Usage](https://www.rabbitmq.com/channels.html#resource-usage) guide to understand how to best configure `:max_channels_per_connection`.

⚠️ Please consult the [Detecting Dead TCP Connections with Heartbeats and TCP Keepalives](https://www.rabbitmq.com/heartbeats.html) guide to understand how to best configure `:heartbeat_interval_sec`.

## Balanced performance and reliability

The RabbitMQ modules are pre-configured with sensible defaults and follow design principles that improve and delicately balance both performance _and_ reliability.

This has been possible through

-   a) extensive experience of working with Elixir and RabbitMQ in production; _and_
-   b) meticulous consultation of the below (and more) documents and guides.

⚠️ While most of the heavy-lifting is provided by the library itself, reading through the documents below before running _any_ application in production is thoroughly recommended.

-   [Connections](https://www.rabbitmq.com/connections.html)
-   [Channels](https://www.rabbitmq.com/channels.html)
-   [Reliability Guide](https://www.rabbitmq.com/reliability.html)
-   [Publisher Confirms](https://www.rabbitmq.com/confirms.html#publisher-confirms)
-   [Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/confirms.html)
-   [Consumer Acknowledgement Modes and Data Safety Considerations](https://www.rabbitmq.com/confirms.html#acknowledgement-modes)
-   [Consumer Prefetch](https://www.rabbitmq.com/consumer-prefetch.html)
-   [Production Checklist](https://www.rabbitmq.com/production-checklist.html)
-   [RabbitMQ Best Practices](https://www.cloudamqp.com/blog/2017-12-29-part1-rabbitmq-best-practice.html)
-   [RabbitMQ Best Practice for High Performance (High Throughput)](https://www.cloudamqp.com/blog/2018-01-08-part2-rabbitmq-best-practice-for-high-performance.html)

## Consistency

The RabbitMQ modules are designed to help you build consistent, SDK-like Consumers and Producers.

```elixir
defmodule CustomerProducer do
  use RabbitMQ.Producer, exchange: "customer"

  @doc """
  Publishes an event routed via "customer.created".
  """
  def customer_created(customer_id) do
    opts = [
      content_type: "application/json",
      correlation_id: UUID.uuid4(),
      mandatory: true
    ]

    payload = Jason.encode!(%{version: "1.0.0", customer_id: customer_id})

    publish(payload, "customer.created", opts)
  end

  @doc """
  Publishes an event routed via "customer.created".
  """
  def customer_updated(customer_data) do
    opts = [
      content_type: "application/json",
      correlation_id: UUID.uuid4(),
      mandatory: true
    ]

    payload = Jason.encode!(%{version: "1.0.0", customer_data: customer_data})

    publish(payload, "customer.created", opts)
  end
end
```

## TODO

A quick and dirty tech-debt tracker, used in conjunction with Issues.

-   [ ] Add support for notifying the parent producer when a publisher `nack` occurs.
