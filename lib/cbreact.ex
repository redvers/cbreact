defmodule Cbreact do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    :ok = :hackney_pool.start_pool(:cbpool, [timeout: 150000, max_connections: 500])

    children = [
      # Start the endpoint when the application starts
      supervisor(Cbreact.Endpoint, []),
      supervisor(Cbreact.Session.Supervisor, []),
      # Here you could define other workers and supervisors as children
      # worker(Cbreact.Eventseeker, []),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cbreact.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Cbreact.Endpoint.config_change(changed, removed)
    :ok
  end
end
