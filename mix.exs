defmodule MQ.MixProject do
  use Mix.Project

  def project do
    [
      app: :rabbit_mq,
      version: "0.0.0-alpha-1",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix]
      ],
      docs: docs(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:lager, :logger, :amqp]
    ]
  end

  defp docs do
    [
      filter_prefix: "RabbitMQ",
      main: "overview",
      extra_section: "GUIDES",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      nest_modules_by_prefix: [RabbitMQ.Consumer, RabbitMQ.Producer]
    ]
  end

  defp extras do
    [
      # License
      "LICENSE.md",

      # Introduction
      "guides/introduction/overview.md",
      "guides/introduction/configuration.md",

      # Advanced
      "guides/advanced/topology.md",
      "guides/advanced/consumers.md",
      "guides/advanced/producers.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\//,
      Advanced: ~r/guides\/advanced\//
    ]
  end

  defp package do
    [
      # These are the default files included in the package
      files: ~w(lib mix.exs README.md),
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/hqoss/rabbit_mq"},
      maintainers: ["Slavo Vojacek"]
    ]
  end

  defp description do
    "🐇 The missing Elixir client for RabbitMQ"
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 1.4"},
      {:uuid, "~> 1.1"},
      # Dev/Test-only deps
      {:ex_check, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:sobelow, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(env) when env in [:test, :ci], do: ["lib", "test/rabbit_mq"]
  defp elixirc_paths(_), do: ["lib"]

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      # test: ["rabbit.init", "test"]
    ]
  end
end
