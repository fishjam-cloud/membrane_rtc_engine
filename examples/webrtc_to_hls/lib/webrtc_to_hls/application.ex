defmodule WebRTCToHLS.Application do
  @moduledoc false
  use Application

  require Membrane.Logger

  @impl true
  def start(_type, _args) do
    children = [
      WebRTCToHLSWeb.Endpoint,
      {Phoenix.PubSub, name: WebRTCToHLS.PubSub}
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
