defmodule Simulation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = [
      example: [
        strategy: Cluster.Strategy.Gossip,
        config: [
        #   hosts: [
        #     :"a@macerick", :"a2@macerick", :"b@e-pc"
        #   ]
        secret: "2"
        ]
      ]
    ]
    children = [
      {Cluster.Supervisor, [topologies, [name: Simulation.ClusterSupervisor]]},
      # Starts a worker by calling: Simulation.Worker.start_link(arg)
      {Simulation.Worker, :initial_state}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Simulation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
