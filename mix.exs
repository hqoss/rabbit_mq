defmodule MQ.MixProject do
  use Mix.Project

  def project do
    [
      app: :rabbitex,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MQ.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 1.3"},
      {:jason, "~> 1.1"},
      {:poolboy, "~> 1.5.1"},
      # Test deps
      {:credo, "~> 1.1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
