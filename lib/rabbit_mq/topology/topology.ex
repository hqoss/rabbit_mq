defmodule RabbitMQ.Topology do
  @moduledoc """
  A convenience module that can be used to establish the (RabbitMQ) network topology.

  First, create a module that `use`s `RabbitMQ.Topology` to define exchanges and their
  corresponding bindings as shown below.

  ⚠️ Please note that exclusive queues cannot be configured here. You may need to consult
  the `RabbitMQ.Consumer` module for details on how exclusive queues can be set up and used.

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

  Then, simply add this module to your supervision tree, *before* any Consumers or Producers
  that rely on the exchanges configured within it start.

  ⚠️ Please note that the `Topology` module will terminate gracefully as soon as the
  network is configured.

      children = [
        Topology,
        MyConsumer,
        MyProducer,
        # ...and more
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """

  @doc """
  The macro to `use` this module.

  Available options:

      exchanges: [
        {
          # Exchange name
          "customer",
          # Exchange type, only topic is supported at the moment
          :topic,
          # List of bindings
          [
            {
              # Routing/binding key
              "#",
              # Queue name
              "customer/#",
              # Queue opts (optional)
              durable: true
            }
          ],
          # Exchange opts
          durable: true
        }
      ]
  """
  defmacro __using__(opts) do
    quote do
      alias AMQP.{Channel, Connection, Exchange, Queue}

      require Logger

      # See https://hexdocs.pm/elixir/Supervisor.html#module-restart-values-restart.
      # `:transient` - the child process is restarted only if it terminates abnormally,
      # i.e., with an exit reason other than `:normal`, `:shutdown`, or `{:shutdown, term}`.
      use GenServer, restart: :transient

      @amqp_url Application.get_env(:rabbit_mq_ex, :amqp_url)

      @exchanges unquote(Keyword.get(opts, :exchanges, []))
      @this_module __MODULE__

      ##############
      # Public API #
      ##############

      def start_link(_args) do
        GenServer.start_link(@this_module, nil, name: @this_module)
      end

      ######################
      # Callback Functions #
      ######################

      @impl true
      def init(_arg) do
        with {:ok, connection} <- Connection.open(@amqp_url),
             {:ok, channel} <- Channel.open(connection) do
          state = Enum.flat_map(@exchanges, &declare_exchange(&1, channel))

          Channel.close(channel)
          Connection.close(connection)

          Process.send_after(self(), :declare_done, 0)

          {:ok, state}
        end
      end

      @impl true
      def handle_info(:declare_done, state) do
        {:stop, :shutdown, state}
      end

      #####################
      # Private Functions #
      #####################

      defp declare_exchange({exchange, :topic, routing_keys, opts}, channel) do
        Logger.debug("Declaring topic exchange #{exchange} with opts: #{inspect(opts)}.")

        :ok = Exchange.topic(channel, exchange, opts)

        routing_keys
        |> Enum.map(&declare_queue(&1, exchange, channel))
        |> Enum.map(&bind_queue/1)
      end

      defp declare_queue({routing_key, queue}, exchange, channel),
        do: declare_queue({routing_key, queue, []}, exchange, channel)

      defp declare_queue({routing_key, queue, opts}, exchange, channel) do
        if Keyword.get(opts, :exclusive) === true do
          raise "Exclusive queues can only be declared through Consumer configuration."
        end

        Logger.debug("Declaring queue #{queue} with opts: #{inspect(opts)}.")

        {:ok, %{queue: queue}} = Queue.declare(channel, queue, opts)
        {routing_key, queue, exchange, channel}
      end

      defp bind_queue({routing_key, queue, exchange, channel}) do
        Logger.debug(
          "Binding queue #{queue} to exchange #{exchange} with routing_key #{routing_key}."
        )

        Queue.bind(channel, queue, exchange, routing_key: routing_key)
        {queue, exchange, routing_key}
      end
    end
  end
end
