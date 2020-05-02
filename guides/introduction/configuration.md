# Configuration

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
