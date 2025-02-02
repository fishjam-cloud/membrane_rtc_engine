defmodule Membrane.RTC.Engine.App do
  @moduledoc false
  use Application

  @impl true
  def start(_start_type, _start_args) do
    children = [
      {Registry, keys: :duplicate, name: Membrane.RTC.Engine.get_registry_name()},
      {Registry, keys: :unique, name: Membrane.RTC.Engine.Registry.PeerConnection}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
