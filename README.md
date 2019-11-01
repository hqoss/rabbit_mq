# rabbit_mq_ex

A better RabbitMQ client.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `rabbitex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rabbitex, "~> 0.1.0"}
  ]
end
```

## Usage

### Producers

In order to publish messages onto an exchange, let's first create a simple Producer.

```elixir
defmodule Bookings.Producers.AirlineRequestProducer do
  alias MQ.Producer

  use Producer, exchange: "airline_request"

  @valid_airline_codes ~w(ba qr)a

  def place_booking(airline_code, %{date_time: _, flight_number: _} = params, opts)
      when airline_code in @valid_airline_codes and is_list(opts) do
    airline = airline(airline_code)
    payload = payload(params)
    opts = opts |> Keyword.put(:routing_key, "#{airline}.place_booking")

    publish(payload, opts)
  end

  def cancel_booking(airline_code, %{booking_id: _} = params, opts)
      when airline_code in @valid_airline_codes and is_list(opts) do
    airline = airline(airline_code)
    payload = payload(params)
    opts = opts |> Keyword.put(:routing_key, "#{airline}.cancel_booking")

    publish(payload, opts)
  end

  defp payload(%{date_time: _, flight_number: _} = params),
    do: params |> Map.take([:date_time, :flight_number]) |> Jason.encode!()

  defp payload(%{booking_id: _} = params),
    do: params |> Map.take([:booking_id]) |> Jason.encode!()

  defp airline(:ba), do: "british_airways"
  defp airline(:qr), do: "qatar_airways"
end

```

In this specific example, we will publish messages onto the `airline_request` exchange, which we are just about to configure and declare in the section below.

### Topology

To set up the exchange and the associated bindings, we will create a `Topology` module that all our services will use to interact with RabbitMQ.

```elixir
defmodule Bookings.Topology do
  alias MQ.Topology

  @exchanges ~w(airline_request)

  @behaviour Topology

  def gen do
    @exchanges |> Enum.map(&exchange/1)
  end

  defp exchange("airline_request" = exchange) do
    {exchange,
     type: :topic,
     durable: true,
     routing_keys: [
       {"*.place_booking",
        queue: "#{exchange}_queue/*.place_booking/bookings_app",
        durable: true,
        dlq: "#{exchange}_dead_letter_queue"},
       {"*.cancel_booking",
        queue: "#{exchange}_queue/*.cancel_booking/bookings_app",
        durable: true,
        dlq: "#{exchange}_dead_letter_queue"}
     ]}
  end
end

```

We will use this to ensure our RabbitMQ setup is consistent across services and all exchanges, queues and bindings are correctly configured before we start our services.

As shown in the example above, we will declare 3 queues:

1) `airline_request_queue/*.place_booking/bookings_app`; used to Consume and process messages associated with _placing_ a booking with a specific airline
2) `airline_request_queue/*.cancel_booking/bookings_app`; used to Consume and process messages associated with _cancelling_ a booking with a specific airline
3) `airline_request_dead_letter_queue`; messages that cannot be delivered or processed will end up here

Please note that the strategy for naming queues is largely dependent on your use case. In the above example, we base it on the following:

`#{exchange_name}_queue/#{routing_key}/#{consuming_app_name}`

### Application configuration

Now that we have our topology defined, let's configure the `:rabbitex` application environment to make use of it.

```elixir
config :rabbitex, :config,
  amqp_url: "amqp://guest:guest@localhost:5672",
  topology: Bookings.Topology

```

This configuration will be used as follows:

* `:amqp_url` by the `MQ.ConnectionManager` module to connect to the broker
* `:topology` by the `mix rabbit.init` script to set up the exchanges, queues, and bindings

### Consumers and message processing

To consume and process messages from the queues above, we will need to create message processors.

```elixir
defmodule Bookings.MessageProcessors.PlaceBookingMessageProcessor do
  require Logger

  @date_format "{WDfull}, {0D} {Mfull} {YYYY}"

  def process_message(payload, _meta) do
    with {:ok, %{"date_time" => date_time_iso, "flight_number" => flight_number}} <-
           Jason.decode(payload),
         {:ok, date_time, _} <- DateTime.from_iso8601(date_time_iso),
         {:ok, formatted_date} <- Timex.format(date_time, @date_format) do
      Logger.info("Attempting to book #{flight_number} for #{formatted_date}.")
      :ok
    end
  end
end

```

```elixir
defmodule Bookings.MessageProcessors.CancelBookingMessageProcessor do
  require Logger

  def process_message(payload, _meta) do
    with {:ok, %{"booking_id" => booking_id}} <- Jason.decode(payload) do
      Logger.info("Attempting to cancel booking #{booking_id}.")
      :ok
    end
  end
end

```

### Putting it all together

Before we put our producers and consumers to work, we need to make sure that the topology is reflected on the RabbitMQ broker we will use with our application. To do this, we will run

```bash
mix rabbit.init

```

You should see the following in the console:

```bash
14:40:34.717 [debug] Declared airline_request_queue/*.place_booking/bookings_app queue: %{args: [{"x-dead-letter-exchange", :longstr, ""}, {"x-dead-letter-routing-key", :longstr, "airline_request_dead_letter_queue"}], durable: true, exchange: "airline_request", exclusive: false, queue: "airline_request_queue/*.place_booking/bookings_app", routing_key: "*.place_booking"}

14:40:34.721 [debug] Declared airline_request_queue/*.cancel_booking/bookings_app queue: %{args: [{"x-dead-letter-exchange", :longstr, ""}, {"x-dead-letter-routing-key", :longstr, "airline_request_dead_letter_queue"}], durable: true, exchange: "airline_request", exclusive: false, queue: "airline_request_queue/*.cancel_booking/bookings_app", routing_key: "*.cancel_booking"}

```

Now, let's create our Application.

```elixir
defmodule Bookings.Application do
  alias MQ.Supervisor, as: MQSupervisor

  alias Bookings.Producers.AirlineRequestProducer

  alias Bookings.MessageProcessors.{
    PlaceBookingMessageProcessor,
    CancelBookingMessageProcessor
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
      {MQSupervisor, opts}
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

Now, let's verify our producers and consumers work as expected. Run `iex -S mix`, then:

To place a booking:

```elixir
iex(1)> Bookings.Producers.AirlineRequestProducer.place_booking(:qr, %{date_time: DateTime.utc_now() |> DateTime.to_iso8601(), flight_number: "QR007"}, [])
:ok
iex(2)>

[info] Attempting to book QR007 for Friday, 01 November 2019.
```

To cancel a booking:

```elixir
iex(1)> Bookings.Producers.AirlineRequestProducer.cancel_booking(:qr, %{booking_id: "baf4dfde-50b1-4d55-9c76-44eae1159325"}, [])
:ok
iex(2)>

[info] Attempting to cancel booking baf4dfde-50b1-4d55-9c76-44eae1159325.
```

### Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/rabbitex](https://hexdocs.pm/rabbitex).
