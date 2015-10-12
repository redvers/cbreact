require Logger
defmodule Cbreact.Session.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_child(sensorid) do
    sessionid = String.to_atom("Session#{:erlang.system_time}")
    Supervisor.start_child(__MODULE__, worker(Cbreact.Session, [sensorid, sessionid], id: sessionid))
  end

  def init(:ok) do
    children = [
    ]

    supervise(children, strategy: :one_for_one)
  end

end
