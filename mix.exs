defmodule MQ.MixProject do
  use Mix.Project

  def project do
    [
      app: :rabbit_mq_ex,
      version: "1.0.0-0.0.1",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
      # mod: {Bookings.Application, []}
    ]
  end

  defp package() do
    [
      # These are the default files included in the package
      files: ~w(lib test/__support .formatter.exs mix.exs README*),
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/qworks-io/rabbit_mq_ex.git"},
      maintainers: ["Slavo Vojacek"]
    ]
  end

  defp description do
    "rabbit_mq_ex contains a set of tools that make working with RabbitMQ consume/produce pipelines easier"
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 1.3"},
      {:jason, "~> 1.1"},
      {:nanoid, "~> 2.0.2"},
      {:poolboy, "~> 1.5.1"},
      {:timex, "~> 3.5"},
      {:uuid, "~> 1.1"},
      # Test deps
      {:ex_check, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:sobelow, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:test, :ci], do: ["lib", "test/__support"]
  defp elixirc_paths(_), do: ["lib"]

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      test: ["rabbit.init", "test"]
    ]
  end
end
