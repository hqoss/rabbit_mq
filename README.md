# MQ

**TODO: Add description**

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

### Configuration

To start with, it's essential to correctly configure the AMQP connection and the exchanges and queues your application will be using.

```elixir
# config/config.exs

config :rabbitex, :config,
  amqp_url: "amqp://guest:guest@localhost:5672",
  exchanges: MyApp.Exchanges
```

The Exchanges module needs to expose a gen/0 function that gives us the desired exchange configuration.

```elixir
defmodule MyApp.Exchanges do
  def gen do
    [
      {"audit_log",
       type: :topic,
       durable: true,
       routing_keys: [
         {"#",
          queue: "audit_log_queue/#/example", durable: true, dlq: "audit_log_dead_letter_queue"}
       ]},
      {"log",
       type: :topic,
       durable: true,
       routing_keys: [
         {"#", queue: "log_queue/#/example", durable: true, dlq: "log_dead_letter_queue"},
         {"*.error",
          queue: "log_queue/*.error/example", durable: true, dlq: "log_dead_letter_queue"},
         {"#", durable: false, exclusive: true, dlq: "log_dead_letter_queue"}
       ]},
      {"test", type: :topic, durable: true, routing_keys: []}
    ]
  end
end

```

### Establishing a Connection

Setting up RabbitMQ in your application should be done via the MQ.Supervisor module.

```elixir
defmodule MyApp do
  alias MQ.Supervisor, as: MQSupervisor

  use Application

  def start(_type, _args) do
    opts = [
      consumers: [
        {AuditLogProcessor, workers: 2, queue: "audit_log_queue/#/my_app"},
        {LogProcessor, workers: 2, queue: "log_queue/#/my_app"}
      ],
      producers: [
        {AuditLogProducer, workers: 3},
        {LogProducer, workers: 6}
      ]
    ]

    children = [
      {MQSupervisor, opts},
      # ... add more children here
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Topology

### Producers

### Consumers

### 

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/rabbitex](https://hexdocs.pm/rabbitex).
