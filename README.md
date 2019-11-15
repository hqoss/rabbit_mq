# rabbit_mq_ex

The missing RabbitMQ client for Elixir.

### Features (out of the box)

* Connection supervision and Channel multiplexing
* Built-in Producer and Consumer pooling (configurable)
* Consistent Topology enforcement
* SDK-like Producer API
* Simple Consumer API with Message Processors
* Testing is first-class (+ built-in testing helpers)
* Trivial configuration
* Real-world exmaples with tests
* ... and more

### TODO

* Add module docs to every module
* Add specs and docs to all public functions
* Add params library for validation (in the Publisher examples)
* Document the testing end-to-end Publish/Consume flow
* Document options, e.g. prefetch, workers, publish_opts (link :amqp lib) etc.
* Set up CI/CD
* Add badges to README!
* ... and more

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `rabbit_mq_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rabbit_mq_ex, "~> 1.0.0-1.0.1"}
  ]
end
```

## Usage

### Producers

In order to publish messages onto an exchange, let's first create a simple Producer.

```elixir
defmodule Bookings.Producers.AirlineRequestProducer do
  use MQ.Producer, exchange: "airline_request"

  @valid_airlines ~w(british_airways qatar_airways)a

  @spec place_booking(atom(), map()) :: :ok
  def place_booking(airline, %{date_time: _, flight_number: _} = params, opts \\ [])
      when airline in @valid_airlines and is_list(opts) do
    payload = params |> Map.take([:date_time, :flight_number]) |> Jason.encode!()
    opts = opts |> Keyword.put(:routing_key, "#{airline}.place_booking")
    publish(payload, opts)
  end

  @spec cancel_booking(atom(), map()) :: :ok
  def cancel_booking(airline, %{booking_id: _} = params, opts \\ [])
      when airline in @valid_airlines and is_list(opts) do
    payload = params |> Map.take([:booking_id]) |> Jason.encode!()
    opts = opts |> Keyword.put(:routing_key, "#{airline}.cancel_booking")
    publish(payload, opts)
  end
end

```

In this specific example, we will publish messages onto the `airline_request` exchange, which we are just about to configure and declare in the section below.

### Topology

To set up the exchange and the associated bindings, let's configure `rabbit_mq_ex`.

* `:amqp_url` will be used by the `MQ.ConnectionManager` module to connect to the broker
* `:topology` will be used by the `mix rabbit.init` script to set up the exchanges, queues, and bindings

It's recommended to configure your topology in the "global" `config.exs`, as it ought to be identical across environments.

```elixir
use Mix.Config

config :rabbit_mq_ex, :topology, [
  {"airline_request",
   type: :topic,
   durable: true,
   routing_keys: [
     {"*.place_booking",
      queue: "airline_request_queue/*.place_booking/bookings_app",
      durable: true,
      dlq: "airline_request_dead_letter_queue"},
     {"*.cancel_booking",
      queue: "airline_request_queue/*.cancel_booking/bookings_app",
      durable: true,
      dlq: "airline_request_dead_letter_queue"}
   ]}
]

import_config "#{Mix.env()}.exs"
```

As for the connection to the broker, you may want to configure this separately in each of your environment-specific configs, e.g. `dev.exs` or `test.exs`.

```elixir
use Mix.Config

config :rabbit_mq_ex, :amqp_url, "amqp://guest:guest@localhost:5672"

```

We will use this approach to ensure our RabbitMQ setup is consistent across services and all exchanges, queues and bindings are correctly configured before we start our services.

As shown in the example above, we will declare 3 queues:

1) `airline_request_queue/*.place_booking/bookings_app`; used to Consume and process messages associated with _placing_ a booking with a specific airline
2) `airline_request_queue/*.cancel_booking/bookings_app`; used to Consume and process messages associated with _cancelling_ a booking with a specific airline
3) `airline_request_dead_letter_queue`; messages that cannot be delivered or processed will end up here

Please note that the strategy for naming queues is largely dependent on your use case. In the above example, we base it on the following:

`#{exchange_name}_queue/#{routing_key}/#{consuming_app_name}`

To set this up, make sure you have Rabbit MQ running locally and can connect to it, then run:

```bash
mix rabbit.init

```

You should see the following in the console:

```bash
[debug] Declared airline_request_queue/*.place_booking/bookings_app queue: %{args: [{"x-dead-letter-exchange", :longstr, ""}, {"x-dead-letter-routing-key", :longstr, "airline_request_dead_letter_queue"}], durable: true, exchange: "airline_request", exclusive: false, queue: "airline_request_queue/*.place_booking/bookings_app", routing_key: "*.place_booking"}

[debug] Declared airline_request_queue/*.cancel_booking/bookings_app queue: %{args: [{"x-dead-letter-exchange", :longstr, ""}, {"x-dead-letter-routing-key", :longstr, "airline_request_dead_letter_queue"}], durable: true, exchange: "airline_request", exclusive: false, queue: "airline_request_queue/*.cancel_booking/bookings_app", routing_key: "*.cancel_booking"}

```

### Consumers and message processing

To consume and process messages from the queues above, we will need to create message processors.

The `*.place_booking` message processor might look like this:

```elixir
defmodule Bookings.MessageProcessors.PlaceBookingMessageProcessor do
  alias Bookings.Store

  import Bookings.Core.DateTimeFormatter, only: [format_iso_date_time: 2]

  require Logger

  @date_format "{WDfull}, {0D} {Mfull} {YYYY}"

  @type error() :: :invalid_payload | Jason.DecodeError | :invalid_format

  @doc """
  Processes `*.place_booking` messages from the `airline_request` exchange.
  Calls a 3rd party API to place a booking, saves the booking into `Bookings.Store`.
  """
  @spec process_message(String.t(), map()) :: :ok | {:error, error()}
  def process_message(payload, _meta) do
    with {:ok, message} <- parse_message(payload),
         {:ok, formatted_date} <- format_iso_date_time(message.date_time, @date_format) do
      Logger.info("Attempting to book #{message.flight_number} for #{formatted_date}.")

      # Fake HTTP call to a 3rd party, receive `external_booking_id`,
      # for example: `AirlineClient.place_booking(message)`.
      external_booking_id = UUID.uuid4()

      attrs = Map.merge(message, %{external_booking_id: external_booking_id})

      # Not matching this would result in an exception which will fall
      # back to `{:error, :retry_once}`, so we let it fail.
      {:ok, booking} = Store.insert(attrs)

      Logger.info("Successfully booked #{inspect(booking)}.")

      :ok
    end
  end

  defp parse_message(payload) do
    case Jason.decode(payload) do
      {:ok, %{"date_time" => date_time, "flight_number" => flight_number}} ->
        {:ok, %{date_time: date_time, flight_number: flight_number}}

      {:ok, _} ->
        {:error, :invalid_payload}

      error ->
        error
    end
  end
end

```

And then the `*.cancel_booking` message processor:

```elixir
defmodule Bookings.MessageProcessors.CancelBookingMessageProcessor do
  alias Bookings.Store

  require Logger

  @type error() :: :invalid_payload | Jason.DecodeError | :not_found

  @doc """
  Processes `*.cancel_booking` messages from the `airline_request` exchange.
  Calls a 3rd party API to cancel a booking, removes the booking from `Bookings.Store`.
  """
  @spec process_message(String.t(), map()) :: :ok | {:error, error()}
  def process_message(payload, _meta) do
    with {:ok, message} <- parse_message(payload),
         {:ok, booking} <- Store.get_existing(message.booking_id) do
      %{id: booking_id, external_booking_id: external_booking_id} = booking

      Logger.info("Attempting to cancel #{booking_id}, external id: #{external_booking_id}.")

      # Fake HTTP call to a 3rd party to cancel the booking, using `external_booking_id`,
      # for example: `AirlineClient.cancel_booking(external_booking_id)`.

      :ok = Store.delete(booking_id)

      Logger.info("Booking #{booking_id} successfully cancelled.")

      :ok
    end
  end

  defp parse_message(payload) do
    case Jason.decode(payload) do
      {:ok, %{"booking_id" => booking_id}} ->
        {:ok, %{booking_id: booking_id}}

      {:ok, _} ->
        {:error, :invalid_payload}

      error ->
        error
    end
  end
end

```

## Putting it all together

### 1) Declare your topology

Before we put our producers and consumers to work, we need to make sure that the topology is reflected on the RabbitMQ broker we will use with our application. To do this, we will run

```bash
mix rabbit.init

```

You should see the following in the console:

```bash
[debug] Declared airline_request_queue/*.place_booking/bookings_app queue: %{args: [{"x-dead-letter-exchange", :longstr, ""}, {"x-dead-letter-routing-key", :longstr, "airline_request_dead_letter_queue"}], durable: true, exchange: "airline_request", exclusive: false, queue: "airline_request_queue/*.place_booking/bookings_app", routing_key: "*.place_booking"}

[debug] Declared airline_request_queue/*.cancel_booking/bookings_app queue: %{args: [{"x-dead-letter-exchange", :longstr, ""}, {"x-dead-letter-routing-key", :longstr, "airline_request_dead_letter_queue"}], durable: true, exchange: "airline_request", exclusive: false, queue: "airline_request_queue/*.cancel_booking/bookings_app", routing_key: "*.cancel_booking"}

```

### 2) Add `MQSupervisor` to your application

Let's create a sample Application using the code we've already written.

```elixir
defmodule Bookings.Application do
  @moduledoc """
  Describes the entire produce/consume workflow.

  For demonstration purposes only!

  You would most likely structure your applications differently,
  for example the corresponding producers and consumers would
  live in separate services/apps. 
  """

  alias MQ.Supervisor, as: MQSupervisor

  alias Bookings.Producers.AirlineRequestProducer
  alias Bookings.Store

  alias Bookings.MessageProcessors.{
    CancelBookingMessageProcessor,
    PlaceBookingMessageProcessor
  }

  use Application

  def start(_type, _args) do
    opts = [
      consumers: [
        {PlaceBookingMessageProcessor,
         queue: "airline_request_queue/*.place_booking/bookings_app"},
        {CancelBookingMessageProcessor,
         queue: "airline_request_queue/*.cancel_booking/bookings_app"}
      ],
      producers: [
        AirlineRequestProducer
      ]
    ]

    children = [
      {MQSupervisor, opts},
      {Store, []}
      # ... add more children here
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

```

In `mix.exs`:

```elixir
  def application do
    [
      mod: {Bookings.Application, []}
    ]
  end
```

Your application will now look like this:

![Application](./application.png)

### 3) Configure `MQSupervisor` according to your needs

You will notice that both the consumers and the producers are pooled, and the **default number of workers is 3**. You can change this in the opts:

```elixir
    opts = [
      consumers: [
        {PlaceBookingMessageProcessor,
         queue: "airline_request_queue/*.place_booking/bookings_app",
         workers: 6},
        {CancelBookingMessageProcessor,
         queue: "airline_request_queue/*.cancel_booking/bookings_app",
         workers: 2}
      ],
      producers: [
        {AirlineRequestProducer, workers: 2}
      ]
    ]
```

### 4) Test in `iex`

Now, let's verify our producers and consumers work as expected. Run `iex -S mix`, then:

To place a booking:

```elixir
iex(1)> payload = %{date_time: "2019-11-08T10:25:00.000000Z", flight_number: "QR007"}
%{date_time: "2019-11-08T10:25:00.000000Z", flight_number: "QR007"}
iex(2)> Bookings.Producers.AirlineRequestProducer.place_booking(:qatar_airways, payload, [])
:ok

[info] Attempting to book QR007 for Friday, 08 November 2019.

[info] Successfully booked %{date_time: "2019-11-08T10:25:00.000000Z", external_booking_id: "4544d317-53e4-4827-a66b-ba3e48aed0fd", flight_number: "QR007", id: "b379bf61-f99d-47a6-8360-0aaeccd3d4f3", inserted_at: 1573208875278}.
```

To cancel a booking:

```elixir
iex(1)> new_booking_attrs = %{date_time: "2019-11-08T10:25:00.000000Z", flight_number: "QR007", external_booking_id: "e53d026f-af7d-477f-8bd2-49e8da66d1ce"}
%{
  date_time: "2019-11-08T10:25:00.000000Z",
  external_booking_id: "e53d026f-af7d-477f-8bd2-49e8da66d1ce",
  flight_number: "QR007"
}
iex(2)> {:ok, booking} = Bookings.Store.insert(new_booking_attrs)
{:ok,
 %{
   date_time: "2019-11-08T10:25:00.000000Z",
   external_booking_id: "e53d026f-af7d-477f-8bd2-49e8da66d1ce",
   flight_number: "QR007",
   id: "42645924-0d6e-4924-8d5a-9fb9a0da394d",
   inserted_at: 1573209097206
 }}
iex(3)> payload = %{booking_id: booking.id}
%{booking_id: "42645924-0d6e-4924-8d5a-9fb9a0da394d"}
iex(4)> Bookings.Producers.AirlineRequestProducer.cancel_booking(:qatar_airways, payload, [])
:ok

[info] Attempting to cancel 42645924-0d6e-4924-8d5a-9fb9a0da394d, external id: e53d026f-af7d-477f-8bd2-49e8da66d1ce.

[info] Booking 42645924-0d6e-4924-8d5a-9fb9a0da394d successfully cancelled.
```

## Testing

In `config/test.exs`:

```elixir
use Mix.Config

config :rabbit_mq_ex, :config,
  amqp_url: "amqp://guest:guest@localhost:5672",
  topology: Bookings.Topology

```

Then in `test/test_helper.exs`:

```elixir
:ok = MQTest.Support.TestConsumerRegistry.init()
ExUnit.start()
```

It's also strongly recommended to add an alias for your test command so that your RabbitMQ topology is asserted prior to every test run:

```elixir
  defp aliases do
    [
      test: ["rabbit.init", "test"]
    ]
  end

```

### Testing producers

To test our airline request producer, we will try to assert the following:

1) `place_booking/3` supports `qatar_airways` and `british_airways` and sets up the corresponding routing keys, e.g. `qatar_airways.place_booking` and `british_airways.place_booking` upon publish
2) `place_booking/3` adds default metadata to the request, expressly `correlation_id` and `timestamp`
3) `place_booking/3` is capable of setting any metadata (apart from `routing_key` which is configured in its implementation and cannot be overriden)

Later we will, of course, try to assert the same with `cancel_booking/3`.

```elixir
defmodule BookingsTest.Producers.AirlineRequestProducer do
  alias MQ.ConnectionManager
  alias MQTest.Support.{RabbitCase, ExclusiveQueue, TestConsumer}
  alias Bookings.Producers.AirlineRequestProducer

  use RabbitCase

  setup_all do
    assert {:ok, _pid} = start_supervised(AirlineRequestProducer.child_spec())

    # Make sure our tests receive all messages published to the `airline_request`
    # exchange, regardless of the `routing_key` configured (hence `#`).
    assert {:ok, airline_request_queue} =
             ExclusiveQueue.declare(exchange: "airline_request", routing_key: "#")

    # Start the `TestConsumer` module, which consumes messages from a given queue
    # and sends them to a process associated with a test that's being executed.
    #
    # See `TestConsumer.register_reply_to(self())` in the `setup` section below.
    assert {:ok, _pid} = start_supervised(TestConsumer.child_spec(queue: airline_request_queue))

    :ok
  end

  setup do
    # Each test process will register its pid (`self()`) so that we can receive
    # corresponding payloads and metadata published via the `Producer`(s).
    assert {:ok, reply_to} = TestConsumer.register_reply_to(self())

    # Each registration generates a unique identifier which will be used
    # in the `TestConsumer`'s message processor module to look up the pid
    # of the currently running test and send the payload and the metadata
    # to that process.
    publish_opts = [reply_to: reply_to]

    [publish_opts: publish_opts]
  end

  describe "Bookings.Producers.AirlineRequestProducer" do
    test "place_booking/3 only accepts `qatar_airways` and `british_airways` booking requests", %{
      publish_opts: publish_opts
    } do
      payload = %{
        date_time: DateTime.utc_now() |> DateTime.to_iso8601(),
        flight_number: Nanoid.generate_non_secure()
      }

      assert :ok = AirlineRequestProducer.place_booking(:british_airways, payload, publish_opts)
      assert :ok = AirlineRequestProducer.place_booking(:qatar_airways, payload, publish_opts)

      assert_receive({:json, %{}, %{routing_key: "british_airways.place_booking"}}, 250)
      assert_receive({:json, %{}, %{routing_key: "qatar_airways.place_booking"}}, 250)
    end

    test "place_booking/3 produces a message with default metadata", %{publish_opts: publish_opts} do
      date_time = DateTime.utc_now() |> DateTime.to_iso8601()
      flight_number = "QR007"
      payload = %{date_time: date_time, flight_number: flight_number}

      assert :ok = AirlineRequestProducer.place_booking(:qatar_airways, payload, publish_opts)

      assert_receive(
        {:json, %{"date_time" => ^date_time, "flight_number" => ^flight_number},
         %{routing_key: "qatar_airways.place_booking"} = meta},
        250
      )

      assert {:ok, _details} = UUID.info(meta.correlation_id)
      refute meta.timestamp == :undefined

      refute_receive 100
    end

    test "place_booking/3 produces a message with custom metadata, but does not override `routing_key`",
         %{publish_opts: publish_opts} do
      date_time = DateTime.utc_now() |> DateTime.to_iso8601()
      flight_number = "QR007"
      payload = %{date_time: date_time, flight_number: flight_number}

      correlation_id = UUID.uuid4()
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:second)

      publish_opts =
        publish_opts
        |> Keyword.merge(
          app_id: "bookings_app",
          correlation_id: correlation_id,
          headers: [{"authorization", "Bearer abc.123"}],
          routing_key: "unsupported_airline.unsupported_action",
          timestamp: timestamp
        )

      assert :ok = AirlineRequestProducer.place_booking(:qatar_airways, payload, publish_opts)

      assert_receive(
        {:json, %{"date_time" => ^date_time, "flight_number" => ^flight_number},
         %{routing_key: "qatar_airways.place_booking"} = meta},
        250
      )

      assert meta.app_id == "bookings_app"
      assert meta.correlation_id == correlation_id
      assert meta.headers == [{"authorization", :longstr, "Bearer abc.123"}]
      assert meta.timestamp == timestamp
    end

    # ... implement the same for `cancel_booking/3` below
  end
end

```

### Testing message processors

Compared to producers, testing message processors is trivial as these modules are pure workers, free of dependencies.

We will look at how to test the produce/consume flow end-to-end in the next section.

Let's take a lookg at the `PlaceBooking` message processor first:

```elixir
defmodule BookingsTest.MessageProcessors.PlaceBookingMessageProcessor do
  alias Bookings.MessageProcessors.PlaceBookingMessageProcessor
  alias Bookings.Store

  use ExUnit.Case

  setup_all do
    assert {:ok, _pid} = start_supervised(Store)
    :ok
  end

  setup do
    on_exit(fn ->
      Store.delete_all()
    end)

    :ok
  end

  describe "Bookings.MessageProcessors.PlaceBookingMessageProcessor.process_message/2" do
    test "makes a new booking and places it into `Bookings.Store`" do
      payload = %{
        date_time: DateTime.utc_now() |> DateTime.to_iso8601(),
        flight_number: Nanoid.generate_non_secure()
      }

      payload_binary = Jason.encode!(payload)

      assert :ok = PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, [{id, booking}]} = Store.get_all()

      assert booking.id == id
      assert booking.date_time == payload.date_time
      assert booking.flight_number == payload.flight_number
      assert is_binary(booking.external_booking_id) == true
      assert is_integer(booking.inserted_at) == true
    end

    test "returns `{:error, :invalid_payload}` if JSON payload is incomplete" do
      payload = %{
        flight_number: Nanoid.generate_non_secure()
      }

      payload_binary = Jason.encode!(payload)

      assert {:error, :invalid_payload} =
               PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, []} = Store.get_all()
    end

    test "returns `{:error, %Jason.DecodeError{}}` if JSON payload is invalid" do
      payload_binary = "Hey, boss!"

      assert {:error, %Jason.DecodeError{}} =
               PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, []} = Store.get_all()
    end

    test "returns `{:error, :invalid_format}` if `date_time` is invalid" do
      payload = %{
        date_time: "invalid date time",
        flight_number: Nanoid.generate_non_secure()
      }

      payload_binary = Jason.encode!(payload)

      assert {:error, :invalid_format} =
               PlaceBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, []} = Store.get_all()
    end
  end
end

```

And for our `CancelBooking` message processor, we would do something similar:

```elixir
defmodule BookingsTest.MessageProcessors.CancelBookingMessageProcessor do
  alias Bookings.MessageProcessors.CancelBookingMessageProcessor
  alias Bookings.Store

  use ExUnit.Case

  setup_all do
    assert {:ok, _pid} = start_supervised(Store)
    :ok
  end

  setup do
    attrs = %{
      date_time: DateTime.utc_now() |> DateTime.to_iso8601(),
      flight_number: Nanoid.generate_non_secure(),
      external_booking_id: UUID.uuid4()
    }

    {:ok, booking} = Store.insert(attrs)

    on_exit(fn ->
      Store.delete_all()
    end)

    [booking: booking]
  end

  describe "Bookings.MessageProcessors.CancelBookingMessageProcessor.process_message/2" do
    test "cancels an existing booking and removes it from `Bookings.Store`", %{booking: booking} do
      payload = %{booking_id: booking.id}
      payload_binary = Jason.encode!(payload)

      assert :ok = CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:error, :not_found} = Store.get_existing(booking.id)
    end

    test "returns `{:error, :invalid_payload}` if JSON payload is incomplete", %{booking: booking} do
      payload = %{unimportant_key: Nanoid.generate_non_secure()}
      payload_binary = Jason.encode!(payload)

      assert {:error, :invalid_payload} =
               CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, _booking} = Store.get_existing(booking.id)
    end

    test "returns `{:error, %Jason.DecodeError{}}` if JSON payload is invalid", %{
      booking: booking
    } do
      payload_binary = "Hey, boss!"

      assert {:error, %Jason.DecodeError{}} =
               CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, _booking} = Store.get_existing(booking.id)
    end

    test "returns `{:error, :not_found}` if booking not found in `Bookings.Store`", %{
      booking: booking
    } do
      payload = %{booking_id: UUID.uuid4()}
      payload_binary = Jason.encode!(payload)

      assert {:error, :not_found} =
               CancelBookingMessageProcessor.process_message(payload_binary, %{})

      assert {:ok, _booking} = Store.get_existing(booking.id)
    end
  end
end

```

### Testing the produce/consume flow end-to-end

TODO

### Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/rabbit_mq_ex](https://hexdocs.pm/rabbit_mq_ex).
