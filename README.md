![Elixir CI](https://github.com/hqoss/rabbit_mq/workflows/Elixir%20CI/badge.svg)
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/d8c50db737fe4b9bae614e2d06710443)](https://www.codacy.com/gh/hqoss/rabbit_mq?utm_source=github.com&utm_medium=referral&utm_content=hqoss/rabbit_mq&utm_campaign=Badge_Grade)

# 🐇 Elixir RabbitMQ Client

`rabbit_mq` is an opinionated RabbitMQ client to help _you_ build balanced and consistent Consumers and Producers.

## Table of contents

-   [Installation and Usage](#installation-and-usage)

-   [Documentation](#documentation)

-   [Sample usage](#sample-usage)

    -   [Producers](#producers)

    -   [Consumers](#consumers)

    -   [Use under supervision tree](#use-under-supervision-tree)

        -   [Produce and Consume messages](#produce-and-consume-messages)

-   [Configuration](#configuration)

    -   [Excessive logging](#excessive-logging)
    -   [Lager conflicts with Elixir logger](#lager-conflicts-with-elixir-logger)

-   [Testing](#testing)

    -   [Producers](#producers-1)
    -   [Consumers](#consumers-1)

-   [Balanced performance and reliability](#balanced-performance-and-reliability)

-   [TODO](#todo)

## Installation and Usage

Add `:rabbit_mq` as a dependency to your project's `mix.exs`:

```elixir
defp deps do
  [
    {:rabbit_mq, "~> 0.0.1"}
  ]
end
```

## Documentation

The full documentation is [published on hex](https://hexdocs.pm/rabbit_mq/).

The following modules are provided;

-   [`RabbitMQ.Topology`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Topology.html)
-   [`RabbitMQ.Consumer`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Consumer.html)
-   [`RabbitMQ.Producer`](https://hexdocs.pm/rabbit_mq/RabbitMQ.Producer.html)

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

## Testing

The library itself has been rigorously tested, so you should ideally only need to test whether you've configured your modules correctly.

Additionally, you _should_ test any side-effects driven by your Producers or Consumers.

### Producers

Here is a few ideas on how you can test your Producers.

⚠️ The below snippet assumes your application starts the `CustomerProducer` module as shown in earlier examples.

```elixir
defmodule RabbitSampleTest.CustomerProducer do
  alias AMQP.{Basic, Channel, Connection, Queue}
  alias RabbitSample.CustomerProducer

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)
  @exchange "customer"

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Declare an exclusive queue and bind it to the customer exchange.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: "#")

    # Clean up after all tests have ran.
    on_exit(fn ->
      # This queue would have been deleted automatically when the connection
      # gets closed, however we prefer to be explicit. Also, we ensure there
      # are no messages left hanging in the queue.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)

      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel, queue: queue]
  end

  setup %{channel: channel, queue: queue} do
    # Each test will be notified when a message is consumed.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    on_exit(fn ->
      # Ensure there are no messages in the queue as the next test is about to start.
      assert true = Queue.empty?(channel, queue)
    end)

    [
      channel: channel,
      consumer_tag: consumer_tag
    ]
  end

  describe "#{__MODULE__}" do
    test "defines correctly configured child specification", %{
      channel: channel,
      consumer_tag: consumer_tag
    } do
      assert %{
               id: CustomerProducer,
               restart: :permanent,
               shutdown: :brutal_kill,
               start:
                 {RabbitMQ.Producer, :start_link,
                  [
                    %{confirm_type: :async, exchange: @exchange, worker_count: 3},
                    [name: CustomerProducer]
                  ]},
               type: :supervisor
             } = CustomerProducer.child_spec([])

      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "customer_created/1 publishes correctly configured events", %{
      channel: channel,
      consumer_tag: consumer_tag
    } do
      customer_id = UUID.uuid4()
      expected_payload = Jason.encode!(%{v: "1.0.0", customer_id: customer_id})

      assert {:ok, _seq_no} = CustomerProducer.customer_created(customer_id)

      assert_receive(
        {:basic_deliver, ^expected_payload,
         %{
           consumer_tag: ^consumer_tag,
           content_type: "application/json",
           correlation_id: correlation_id,
           delivery_tag: delivery_tag,
           routing_key: "customer.created"
         }}
      )

      # Ensure correlation_id is a valid UUID.
      assert {:ok, _} = UUID.info(correlation_id)

      # Acknowledge that the message has been received.
      Basic.ack(channel, delivery_tag)

      # Stop consuming.
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "customer_updated/1 publishes correctly configured events", %{
      channel: channel,
      consumer_tag: consumer_tag
    } do
      customer_data = %{id: UUID.uuid4()}
      expected_payload = Jason.encode!(%{v: "1.0.0", customer_data: customer_data})

      assert {:ok, _seq_no} = CustomerProducer.customer_updated(customer_data)

      assert_receive(
        {:basic_deliver, ^expected_payload,
         %{
           consumer_tag: ^consumer_tag,
           content_type: "application/json",
           correlation_id: correlation_id,
           delivery_tag: delivery_tag,
           routing_key: "customer.updated"
         }}
      )

      # Ensure correlation_id is a valid UUID.
      assert {:ok, _} = UUID.info(correlation_id)

      # Acknowledge that the message has been received.
      Basic.ack(channel, delivery_tag)

      # Stop consuming.
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end
  end
end
```

### Consumers

Here is a few ideas on how you can test your Consumers.

⚠️ The below snippet assumes your application starts the `CustomerCreatedConsumer` module as shown in earlier examples.

```elixir
defmodule RabbitSampleTest.CustomerCreatedConsumer do
  alias AMQP.{Basic, Channel, Connection, Queue}
  alias RabbitSample.CustomerCreatedConsumer

  import ExUnit.CaptureLog

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)
  @exchange "customer"
  @queue "#{@exchange}/customer.created"

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Declare an exclusive queue and bind it to the customer exchange.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: "#")

    # Clean up after all tests have ran.
    on_exit(fn ->
      # This queue would have been deleted automatically when the connection
      # gets closed, however we prefer to be explicit. Also, we ensure there
      # are no messages left hanging in the queue.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)

      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel, queue: queue]
  end

  setup %{channel: channel, queue: queue} do
    # Each test will be notified when a message is consumed.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    on_exit(fn ->
      # Ensure there are no messages in the queue as the next test is about to start.
      assert true = Queue.empty?(channel, queue)
    end)

    [
      channel: channel,
      consumer_tag: consumer_tag
    ]
  end

  describe "#{__MODULE__}" do
    test "defines correctly configured child specification", %{
      channel: channel,
      consumer_tag: consumer_tag
    } do
      assert %{
               id: CustomerCreatedConsumer,
               restart: :permanent,
               shutdown: :brutal_kill,
               start:
                 {RabbitMQ.Consumer, :start_link,
                  [
                    %{consume_cb: _, prefetch_count: 3, queue: @queue, worker_count: 2},
                    [name: CustomerCreatedConsumer]
                  ]},
               type: :supervisor
             } = CustomerCreatedConsumer.child_spec([])

      # Stop consuming.
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "consume/3 logs a message", %{
      channel: channel,
      consumer_tag: consumer_tag
    } do
      correlation_id = UUID.uuid4()
      payload = Jason.encode!(%{v: "1.0.0", customer_id: UUID.uuid4()})

      Basic.publish(channel, @exchange, "customer.created", payload,
        correlation_id: correlation_id
      )

      assert_receive(
        {:basic_deliver, payload,
         %{
           consumer_tag: ^consumer_tag,
           correlation_id: ^correlation_id,
           routing_key: "customer.created"
         } = meta}
      )

      assert capture_log(fn ->
               CustomerCreatedConsumer.consume(payload, meta, channel)
             end) =~ "Customer #{payload} created"

      # Stop consuming.
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end
  end
end
```

⚠️ The below snippet assumes your application starts the `CustomerUpdatedConsumer` module as shown in earlier examples.

```elixir
defmodule RabbitSampleTest.CustomerUpdatedConsumer do
  alias AMQP.{Basic, Channel, Connection, Queue}
  alias RabbitSample.CustomerUpdatedConsumer

  import ExUnit.CaptureLog

  use ExUnit.Case

  @amqp_url Application.get_env(:rabbit_mq, :amqp_url)
  @exchange "customer"
  @queue "#{@exchange}/customer.updated"

  setup_all do
    assert {:ok, connection} = Connection.open(@amqp_url)
    assert {:ok, channel} = Channel.open(connection)

    # Declare an exclusive queue and bind it to the customer exchange.
    {:ok, %{queue: queue}} = Queue.declare(channel, "", exclusive: true)
    :ok = Queue.bind(channel, queue, @exchange, routing_key: "#")

    # Clean up after all tests have ran.
    on_exit(fn ->
      # This queue would have been deleted automatically when the connection
      # gets closed, however we prefer to be explicit. Also, we ensure there
      # are no messages left hanging in the queue.
      assert {:ok, %{message_count: 0}} = Queue.delete(channel, queue)

      assert :ok = Channel.close(channel)
      assert :ok = Connection.close(connection)
    end)

    [channel: channel, queue: queue]
  end

  setup %{channel: channel, queue: queue} do
    # Each test will be notified when a message is consumed.
    assert {:ok, consumer_tag} = Basic.consume(channel, queue)

    # This will always be the first message received by the process.
    assert_receive({:basic_consume_ok, %{consumer_tag: ^consumer_tag}})

    on_exit(fn ->
      # Ensure there are no messages in the queue as the next test is about to start.
      assert true = Queue.empty?(channel, queue)
    end)

    [
      channel: channel,
      consumer_tag: consumer_tag
    ]
  end

  describe "#{__MODULE__}" do
    test "defines correctly configured child specification", %{
      channel: channel,
      consumer_tag: consumer_tag
    } do
      assert %{
               id: CustomerUpdatedConsumer,
               restart: :permanent,
               shutdown: :brutal_kill,
               start:
                 {RabbitMQ.Consumer, :start_link,
                  [
                    %{consume_cb: _, prefetch_count: 6, queue: @queue, worker_count: 2},
                    [name: CustomerUpdatedConsumer]
                  ]},
               type: :supervisor
             } = CustomerUpdatedConsumer.child_spec([])

      # Stop consuming.
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end

    test "consume/3 logs a message", %{
      channel: channel,
      consumer_tag: consumer_tag
    } do
      correlation_id = UUID.uuid4()
      customer_data = %{id: UUID.uuid4()}
      payload = Jason.encode!(%{v: "1.0.0", customer_data: customer_data})

      Basic.publish(channel, @exchange, "customer.updated", payload,
        correlation_id: correlation_id
      )

      assert_receive(
        {:basic_deliver, payload,
         %{
           consumer_tag: ^consumer_tag,
           correlation_id: ^correlation_id,
           routing_key: "customer.updated"
         } = meta}
      )

      assert capture_log(fn ->
               CustomerUpdatedConsumer.consume(payload, meta, channel)
             end) =~ "Customer updated. Data: #{payload}."

      # Stop consuming.
      Basic.cancel(channel, consumer_tag)

      # This will always be the last message received by the process.
      assert_receive({:basic_cancel_ok, %{consumer_tag: ^consumer_tag}})

      # Ensure no further messages are received.
      refute_receive(_)
    end
  end
end
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

## TODO

A quick and dirty tech-debt tracker, used in conjunction with Issues.

-   [ ] Add support for notifying the parent producer when a publisher `nack` occurs.
-   [ ] Increase test coverage to as close to 100% as possible
-   [ ] Add testing guide
