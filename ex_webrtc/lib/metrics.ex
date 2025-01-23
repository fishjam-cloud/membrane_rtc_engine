defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.Metrics do
  @moduledoc """
  Defines metrics and events for stats received from the ExWebRTC Endpoint
  """

  require Logger

  alias Membrane.RTC.Engine.Endpoint

  @webrtc_event [Endpoint.ExWebRTC, :transport]

  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics() do
    [
      Telemetry.Metrics.sum(
        "ex-webrtc.trasnport.bytes_received_total",
        event_name: @webrtc_event,
        measurement: :bytes_received
      ),
      Telemetry.Metrics.sum(
        "ex-webrtc.transport.bytes_sent_total",
        event_name: @webrtc_event,
        measurement: :bytes_sent
      )
    ]
  end

  @spec emit_transport_event(map(), Keyword.t()) :: :ok
  def emit_transport_event(%{transport: transport}, telemetry_label) do
    :telemetry.execute(
      [Endpoint.ExWebRTC, :transport],
      %{bytes_received: transport.bytes_received, bytes_sent: transport.bytes_sent},
      Map.new(telemetry_label)
    )
  end
end
