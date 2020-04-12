defmodule RabbitMQ.Producer do
  defmacro __using__(opts) do
    quote do
      alias RabbitMQ.Producer

      # alias AMQP.Confirm

      require Logger

      @confirm_type unquote(Keyword.get(opts, :confirm_type, :async))
      @channel_type unquote(Keyword.get(opts, :channel_type, :confirm))
      @confirm_timeout unquote(Keyword.get(opts, :confirm_timeout, 250))
      @exchange unquote(Keyword.get(opts, :exchange, ""))
      @worker_count unquote(Keyword.get(opts, :worker_count, 3))
      @max_workers Application.get_env(:rabbit_mq_ex, :max_channels_per_connection)
      @this_module __MODULE__

      if @worker_count > @max_workers do
        raise "Cannot start #{@worker_count} workers, max is #{@max_workers}!"
      end

      ##############
      # Public API #
      ##############

      def child_spec(opts) do
        init_arg = %{
          connection_name: build_connection_name(),
          confirm_type: @confirm_type,
          confirm_timeout: @confirm_timeout,
          channel_type: @channel_type,
          exchange: @exchange,
          worker_count: @worker_count
        }

        opts = Keyword.put_new(opts, :name, @this_module)

        %{
          id: @this_module,
          start: {Producer, :start_link, [init_arg, opts]},
          type: :supervisor,
          restart: :permanent,
          shutdown: :infinity
        }
      end

      ###########################
      # Useful Helper Functions #
      ###########################

      # defdelegate wait_for_confirms(channel), to: Confirm
      # defdelegate wait_for_confirms(channel, timeout), to: Confirm
      # defdelegate wait_for_confirms_or_die(channel), to: Confirm
      # defdelegate wait_for_confirms_or_die(channel, timeout), to: Confirm

      #####################
      # Private Functions #
      #####################

      defp publish(payload, routing_key, opts)
           when is_binary(payload) and is_binary(routing_key) and is_list(opts) do
        with {:ok, producer_pid} <- GenServer.call(@this_module, :get_producer_pid) do
          GenServer.call(producer_pid, {:publish, @exchange, routing_key, payload, opts})
        end
      end

      defp build_connection_name do
        {:ok, hostname} = :inet.gethostname()
        node = Node.self()
        "#{@this_module}/#{hostname}/#{node}"
      end
    end
  end

  alias AMQP.Connection
  alias RabbitMQ.Producer.Worker
  alias RabbitMQ.Producer.Worker.Config, as: WorkerConfig

  require Logger

  use GenServer

  @amqp_url Application.get_env(:rabbit_mq_ex, :amqp_url)
  @heartbeat_interval_sec Application.get_env(:rabbit_mq_ex, :heartbeat_interval_sec)
  @reconnect_interval_ms Application.get_env(:rabbit_mq_ex, :reconnect_interval_ms)
  @max_channels Application.get_env(:rabbit_mq_ex, :max_channels_per_connection)
  @this_module __MODULE__

  defmodule State do
    @enforce_keys [:connection, :workers, :worker_count]
    defstruct connection: nil, workers: [], worker_count: 0, worker_offset: 0
  end

  ##############
  # Public API #
  ##############

  def start_link(init_arg, opts) do
    GenServer.start_link(@this_module, init_arg, opts)
  end

  ######################
  # Callback Functions #
  ######################

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)

    # Each worker pool will maintain and monitor its own connection.
    {:ok, connection} = connect(args.connection_name)

    config =
      args
      |> Map.take(~w(channel_type confirm_type confirm_timeout)a)
      |> Map.put(:connection, connection)
      |> (&struct(WorkerConfig, &1)).()

    workers =
      1..args.worker_count
      |> Enum.with_index()
      |> Enum.map(fn {_, index} -> start_worker(index, config) end)

    {:ok, %State{connection: connection, workers: workers, worker_count: args.worker_count}}
  end

  @impl true
  def handle_call(
        :get_producer_pid,
        _from,
        %State{worker_offset: worker_offset, workers: workers, worker_count: worker_count} = state
      ) do
    index = rem(worker_offset, worker_count)
    {_index, pid, _init_arg} = Enum.at(workers, index)

    {:reply, {:ok, pid}, %{state | worker_offset: worker_offset + 1}}
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, %State{} = state) do
    Logger.warn("Connection to broker lost due to #{inspect(reason)}.")

    # Stop GenServer; will be restarted by Supervisor. Linked processes will be terminated,
    # and all channels implicitly closed due to the connection process being down.
    {:stop, {:connection_lost, reason}, %{state | connection: nil}}
  end

  @impl true
  def handle_info(
        {:EXIT, from, reason},
        %State{workers: workers} = state
      ) do
    Logger.warn("Producer worker process terminated due to #{inspect(reason)}. Restarting.")

    {index, _old_pid, config} = Enum.find(workers, fn {_index, pid, _config} -> pid === from end)

    updated_workers = List.replace_at(workers, index, start_worker(index, config))

    {:noreply, %{state | workers: updated_workers}}
  end

  #####################
  # Private Functions #
  #####################

  defp connect(name) do
    opts = [channel_max: @max_channels, heartbeat: @heartbeat_interval_sec]

    @amqp_url
    |> Connection.open(name, opts)
    |> case do
      {:ok, connection} ->
        # Get notifications when the connection goes down
        Process.monitor(connection.pid)
        {:ok, connection}

      {:error, error} ->
        Logger.error("Failed to connect to broker due to #{inspect(error)}. Retrying...")
        :timer.sleep(@reconnect_interval_ms)
        connect(name)
    end
  end

  defp start_worker(index, config) do
    {:ok, pid} = Worker.start_link(config)
    {index, pid, config}
  end
end
