defmodule MQ.Producer do
  @doc false

  alias Core.DateTime

  defmacro __using__(opts) do
    quote do
      @doc false
      alias AMQP.{Basic, Channel, Confirm, Connection}
      alias Core.Name
      alias MQ.{ConnectionManager, Producer}

      require Logger

      use GenServer

      defmodule State do
        @enforce_keys [:worker_name]
        defstruct channel: nil, worker_name: nil
      end

      @this_module __MODULE__
      @exchange unquote(opts |> Keyword.fetch!(:exchange))
      @send_timeout 5_000

      @spec start_link(list()) :: GenServer.on_start()
      def start_link(_opts) do
        # Poolboy requires the names to be unique.
        worker_name = @this_module |> Name.module_to_snake_case() |> Name.unique_worker_name()

        GenServer.start_link(@this_module, %State{worker_name: worker_name}, name: worker_name)
      end

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts \\ []) when is_list(opts) do
        workers = opts |> Keyword.get(:workers, 3)

        %{
          id: @this_module,
          start:
            {:poolboy, :start_link,
             [
               [
                 name: {:local, @this_module},
                 # `worker_module: @this_module` makes the entire pool callable
                 # through the module name that `use`s `MQ.Producer`.
                 worker_module: @this_module,
                 size: workers,
                 # Might consider making this an option but in the vast majority
                 # of cases (if not all) you will want this to be `0`.
                 max_overflow: 0
               ],
               opts
             ]}
        }
      end

      @spec publish(String.t(), keyword()) :: :ok
      def publish(payload, opts) do
        :poolboy.transaction(
          @this_module,
          fn pid -> GenServer.call(pid, {:publish, payload, opts}) end,
          @send_timeout
        )
      end

      @impl true
      def init(%State{} = initial_state) do
        request_confirm_channel()
        {:ok, initial_state}
      end

      @impl true
      def handle_call({:publish, _payload, _opts}, _from, %State{channel: nil} = state),
        do: {:reply, {:error, :no_channel}, state}

      @impl true
      def handle_call(
            {:publish, payload, opts},
            _from,
            %State{channel: %Channel{} = channel} = state
          ) do
        opts = opts |> Producer.add_default_metadata()

        with {:ok, routing_key} <- Producer.get_routing_key_from_opts(opts),
             :ok <- Basic.publish(channel, @exchange, routing_key, payload, opts),
             true <- Confirm.wait_for_confirms_or_die(channel) do
          {:reply, :ok, state}
        else
          exception ->
            Logger.error("Failed to publish due to #{inspect(exception)}.")
            {:reply, {:error, :publish_error}, state}
        end
      end

      @impl true
      def handle_info(:request_confirm_channel, %State{worker_name: worker_name} = state) do
        Logger.metadata(worker_name: worker_name)
        Logger.debug("Requesting a confirm channel for #{worker_name}.")

        # See https://hexdocs.pm/amqp/AMQP.Confirm.html for more details.
        {:ok, %Channel{} = channel} = ConnectionManager.request_confirm_channel(worker_name)
        monitor_connection(channel)
        {:noreply, %{state | channel: channel}}
      end

      @impl true
      def handle_info(
            {:DOWN, _, :process, _pid, reason},
            %State{worker_name: worker_name} = state
          ) do
        Logger.metadata(worker_name: worker_name)
        Logger.error("Connection lost due to #{inspect(reason)}.")

        # Stop GenServer. Will be restarted by Supervisor.
        {:stop, {:connection_lost, reason}, state}
      end

      defp request_confirm_channel, do: Process.send_after(self(), :request_confirm_channel, 0)

      # We will get notified when the connection is down
      # and exit the process cleanly.
      #
      # See how we handle `{:DOWN, _, :process, _pid, reason}`.
      defp monitor_connection(%Channel{conn: %Connection{pid: pid}}), do: Process.monitor(pid)
    end
  end

  @spec get_routing_key_from_opts(list()) ::
          {:ok, String.t()} | {:error, :missing_or_invalid_routing_key}
  def get_routing_key_from_opts(opts) when is_list(opts) do
    opts
    |> Keyword.fetch(:routing_key)
    |> case do
      {:ok, routing_key} when is_binary(routing_key) -> {:ok, routing_key}
      _ -> {:error, :missing_or_invalid_routing_key}
    end
  end

  @spec add_default_metadata(list()) :: list()
  def add_default_metadata(opts) do
    opts
    |> Keyword.put_new(:correlation_id, UUID.uuid4())
    |> Keyword.put_new(:timestamp, DateTime.now_unix())
  end
end
