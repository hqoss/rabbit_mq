# Overview

`rabbit_mq` is an opinionated RabbitMQ client to help _you_ build balanced and consistent Consumers and Producers.

The following modules are provided;

-   `RabbitMQ.Topology`
-   `RabbitMQ.Consumer`
-   `RabbitMQ.Producer`

## Sample usage

⚠️ The following examples assume you've already set up your (RabbitMQ) routing topology as shown below.

ℹ️ Consult the `RabbitMQ.Topology` module to learn how to quickly establish desired routing topology.

| source_name | source_kind | destination_name          | destination_kind | routing_key      | arguments |
| ----------- | ----------- | ------------------------- | ---------------- | ---------------- | --------- |
| customer    | exchange    | customer/customer.created | queue            | customer.created | \[]       |
| customer    | exchange    | customer/customer.updated | queue            | customer.updated | \[]       |

As seen in the RabbitMQ Management dashboard:

![RabbitMQ Topology](assets/rabbitmq-topology.png)

First, ensure you point to a valid `amqp_url` by configuring `:rabbit_mq` in your `config.exs`.

```elixir
config :rabbit_mq, :amqp_url, "amqp://guest:guest@localhost:5672"
```

ℹ️ For advanced configuration options, consult the [Configuration section](#configuration).

### Producers

Let's define our `CustomerProducer` first. We will use this module to publish messages onto the `"customer"` exchange.

```elixir
defmodule RabbitSample.CustomerProducer do
  @moduledoc """
  Publishes pre-configured events onto the "customer" exchange.
  """

  use RabbitMQ.Producer, exchange: "customer", worker_count: 3

  @doc """
  Publishes an event routed via "customer.created".
  """
  def customer_created(customer_id) when is_binary(customer_id) do
    opts = [
      content_type: "application/json",
      correlation_id: UUID.uuid4(),
      mandatory: true
    ]

    payload = Jason.encode!(%{v: "1.0.0", customer_id: customer_id})

    publish(payload, "customer.created", opts)
  end

  @doc """
  Publishes an event routed via "customer.updated".
  """
  def customer_updated(updated_customer) when is_map(updated_customer) do
    opts = [
      content_type: "application/json",
      correlation_id: UUID.uuid4(),
      mandatory: true
    ]

    payload = Jason.encode!(%{v: "1.0.0", customer_data: updated_customer})

    publish(payload, "customer.updated", opts)
  end
end
```

⚠️ Please note that all Producer workers implement "reliable publishing". Each Producer worker handles its publisher confirms _asynchronously_, striking a delicate balance between performance and reliability.

To understand why this is important, please refer to the [reliable publishing implementation guide](https://www.rabbitmq.com/tutorials/tutorial-seven-java.html).

ℹ️ In the unlikely event of an unexpected Publisher `nack`, your server will be notified via the `on_unexpected_nack/2` callback, letting you handle such exceptions in any way you see fit.

### Consumers

To consume messages off the respective queues, we will define 2 separate consumers.

⚠️ Please note that automatic message acknowledgement is **disabled** in `rabbit_mq`, therefore it's _your_ responsibility to ensure messages are `ack`'d or `nack`'d.

ℹ️ Please consult the [Consumer Acknowledgement Modes and Data Safety Considerations](https://www.rabbitmq.com/confirms.html#acknowledgement-modes) for more details.

```elixir
defmodule RabbitSample.CustomerCreatedConsumer do
  use RabbitMQ.Consumer, queue: "customer/customer.created", worker_count: 2, prefetch_count: 3

  require Logger

  def consume(payload, meta, channel) do
    Logger.info("Customer #{payload} created.")
    ack(channel, meta.delivery_tag)
  end
end
```

```elixir
defmodule RabbitSample.CustomerUpdatedConsumer do
  use RabbitMQ.Consumer, queue: "customer/customer.updated", worker_count: 2, prefetch_count: 6

  require Logger

  def consume(payload, meta, channel) do
    Logger.info("Customer updated. Data: #{payload}.")
    ack(channel, meta.delivery_tag)
  end
end
```

### Use under supervision tree

And finally, we will start our application.

ℹ️ To run RabbitMQ locally, see our [docker-compose.yaml](docker-compose.yaml) for a sample Docker Compose set up.

```elixir
defmodule RabbitSample.Application do
  use Application

  def start(_type, _args) do
    children = [
      RabbitSample.CustomerProducer,
      RabbitSample.CustomerCreatedConsumer,
      RabbitSample.CustomerUpdatedConsumer
    ]

    opts = [strategy: :one_for_one, name: RabbitSample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Using `iex`;

```bash
iex -S mix
```

The resulting application topology should look like this:

![Application Topology](assets/application-topology.png)

Upon closer inspection using the RabbitMQ Management dashboard, we see that:

-   a) each of our modules maintains its dedicated connection; and
-   b) each of our modules' workers maintains its dedicated channel under the respective connection.

![Connections](assets/rabbitmq-connections.png)

ℹ️ Detailed view of how individual workers have set up their channels. Note that the **different prefetch counts** correspond to the different configuration we provided in our Consumers, and that the Producer's 3 worker channels operate in **Confirm mode**.

![Channels](assets/rabbitmq-channels.png)

#### Produce and Consume messages

```elixir
iex(1)> RabbitSample.CustomerProducer.customer_created(UUID.uuid4())
{:ok, 1}

14:07:22.058 application=rabbit_mq domain=elixir file=lib/rabbit_mq/producer/producer_worker.ex function=handle_info/2 line=84 mfa=RabbitMQ.Producer.Worker.handle_info/2 module=RabbitMQ.Producer.Worker pid=<0.317.0> [debug] Received ACK of 1.

14:07:22.058 application=rabbit_sample domain=elixir file=lib/rabbit_sample/customer_created_consumer.ex function=consume/3 line=7 mfa=RabbitSample.CustomerCreatedConsumer.consume/3 module=RabbitSample.CustomerCreatedConsumer pid=<0.378.0> [info]  Customer {"customer_id":"e79eae21-b8a4-4907-9795-5aa633a9d3df","v":"1.0.0"} created.

iex(2)> RabbitSample.CustomerProducer.customer_updated(%{id: UUID.uuid4()})
{:ok, 1}

14:07:39.247 application=rabbit_sample domain=elixir file=lib/rabbit_sample/customer_updated_consumer.ex function=consume/3 line=7 mfa=RabbitSample.CustomerUpdatedConsumer.consume/3 module=RabbitSample.CustomerUpdatedConsumer pid=<0.381.0> [info]  Customer updated. Data: {"customer_data":{"id":"eee24a7e-ce7b-4eec-8d5f-47ee98f1ca6f"},"v":"1.0.0"}.

14:07:39.247 application=rabbit_mq domain=elixir file=lib/rabbit_mq/producer/producer_worker.ex function=handle_info/2 line=84 mfa=RabbitMQ.Producer.Worker.handle_info/2 module=RabbitMQ.Producer.Worker pid=<0.323.0> [debug] Received ACK of 1.

iex(3)>
```

## Configuration

The following options can be configured.

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

### Excessive logging

See [original section in `amqp` docs](https://github.com/pma/amqp#log-related-to-amqp-supervisors-are-too-verbose).

Add the following configuration.

```elixir
config :logger, handle_otp_reports: false
```

### Lager conflicts with Elixir logger

Lager is used by `rabbit_common` and is not Elixir's best friend yet. You need a workaround.

⚠️ In `mix.exs`, you have to load `:lager` before `:logger`.

```elixir
  extra_applications: [:lager, :logger]
```

## Balanced performance and reliability

The RabbitMQ modules are pre-configured with sensible defaults and follow design principles that improve and delicately balance both performance _and_ reliability.

This has been possible through

-   a) extensive experience of working with Elixir and RabbitMQ in production; _and_
-   b) meticulous consultation of the below (and more) documents and guides.

⚠️ While most of the heavy-lifting is provided by the library itself, reading through the documents below before running _any_ application in production is thoroughly recommended.

-   [Connections](https://www.rabbitmq.com/connections.html)
-   [Channels](https://www.rabbitmq.com/channels.html)
-   [Reliability Guide](https://www.rabbitmq.com/reliability.html)
-   [Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/confirms.html)
-   [Consumer Acknowledgement Modes and Data Safety Considerations](https://www.rabbitmq.com/confirms.html#acknowledgement-modes)
-   [Reliable publishing with publisher confirms](https://www.rabbitmq.com/tutorials/tutorial-seven-java.html)
-   [Consumer Prefetch](https://www.rabbitmq.com/consumer-prefetch.html)
-   [Production Checklist](https://www.rabbitmq.com/production-checklist.html)
-   [RabbitMQ Best Practices](https://www.cloudamqp.com/blog/2017-12-29-part1-rabbitmq-best-practice.html)
-   [RabbitMQ Best Practice for High Performance (High Throughput)](https://www.cloudamqp.com/blog/2018-01-08-part2-rabbitmq-best-practice-for-high-performance.html)
