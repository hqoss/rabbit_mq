# Overview

`rabbit_mq` is an opinionated RabbitMQ client to help _you_ build balanced and consistent Consumers and Producers.

## Documentation

The full documentation is published on [hex](https://hexdocs.pm/rabbit_mq/).

The following modules are provided;

* [`RabbitMQ.Topology`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Topology.html)
* [`RabbitMQ.Consumer`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Consumer.html)
* [`RabbitMQ.Producer`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Producer.html)

## Example usage

1. Define network topology
2. Define Producers
3. Define Consumers
4. Supervise
5. Start producing and consuming messages

### Define network topology

```elixir
defmodule Topology do
  use RabbitMQ.Topology,
    exchanges: [
      {"customer", :topic,
        [
          {"customer.created", "customer/customer.created", durable: true},
          {"customer.updated", "customer/customer.updated", durable: true},
          {"#", "customer/#"}
        ], durable: true}
    ]
end
```

### Define Producers

```elixir
defmodule CustomerProducer do
  use RabbitMQ.Producer, exchange: "customer", worker_count: 3

  def customer_updated(updated_customer) when is_map(updated_customer) do
    opts = [
      content_type: "application/json",
      correlation_id: UUID.uuid4(),
      mandatory: true
    ]

    payload = Jason.encode!(updated_customer)

    publish(payload, "customer.updated", opts)
  end
end
```

### Define Consumers

```elixir
defmodule CustomerConsumer do
  use RabbitMQ.Consumer, queue: "customer/customer.updated", worker_count: 3

  require Logger

  def consume(payload, meta, channel) do
    Logger.info(payload)
    ack(channel, meta.delivery_tag)
  end
end
```

### Supervise

Start as normal under your existing supervision tree.

⚠️ Please note that the `Topology` module will terminate gracefully as soon as the network is configured.

```elixir
children = [
  Topology,
  CustomerConsumer,
  CustomerProducer,
  # ...and more
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Start producing and consuming messages

To publish, simply call your pre-defined methods.

```elixir
CustomerProducer.customer_updated(updated_customer)
```

To consume, use the `consume/3` implementation.

## Balanced performance and reliability

The RabbitMQ modules are pre-configured with sensible defaults and follow design principles that improve and delicately balance both performance _and_ reliability.

This has been possible through

* a) extensive experience of working with Elixir and RabbitMQ in production; _and_
* b) meticulous consultation of the below (and more) documents and guides.

⚠️ While most of the heavy-lifting is provided by the library itself, reading through the documents below before running _any_ application in production is thoroughly recommended.

* [Connections](https://www.rabbitmq.com/connections.html)
* [Channels](https://www.rabbitmq.com/channels.html)
* [Reliability Guide](https://www.rabbitmq.com/reliability.html)
* [Publisher Confirms](https://www.rabbitmq.com/confirms.html#publisher-confirms)
* [Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/confirms.html)
* [Consumer Acknowledgement Modes and Data Safety Considerations](https://www.rabbitmq.com/confirms.html#acknowledgement-modes)
* [Consumer Prefetch](https://www.rabbitmq.com/consumer-prefetch.html)
* [Production Checklist](https://www.rabbitmq.com/production-checklist.html)
* [RabbitMQ Best Practices](https://www.cloudamqp.com/blog/2017-12-29-part1-rabbitmq-best-practice.html)
* [RabbitMQ Best Practice for High Performance (High Throughput)](https://www.cloudamqp.com/blog/2018-01-08-part2-rabbitmq-best-practice-for-high-performance.html)
