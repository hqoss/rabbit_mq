defmodule RabbitMQ.Topology do
  defmacro __using__(opts) do
    quote do
      alias AMQP.{Connection, Channel, Exchange, Queue}

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

      def start_link(_) do
        GenServer.start_link(@this_module, nil, name: @this_module)
      end

      ######################
      # Callback Functions #
      ######################

      @impl true
      def init(_) do
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
