defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.PeerConnectionHandler.Metrics do
  @moduledoc false
  # Defines metrics and events for stats received from the PeerConnection

  require Membrane.TelemetryMetrics

  alias ExWebRTC.MediaStreamTrack

  alias Membrane.RTC.Engine.Endpoint
  alias Membrane.TelemetryMetrics

  @type rtc_stats_report :: %{required(atom() | integer()) => map()}

  @inbound_rtp_event [Endpoint.ExWebRTC, :rtp, :inbound]
  @packet_received_event [Endpoint.ExWebRTC, :rtp, :inbound, :packet]

  @outbound_rtp_event [Endpoint.ExWebRTC, :rtp, :outbound]
  @packet_sent_event [Endpoint.ExWebRTC, :rtp, :outbound, :packet]

  @remote_candidate_event [Endpoint.ExWebRTC, :candidate, :remote]

  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics() do
    inbound_metrics() ++ outbound_metrics() ++ remote_candidate()
  end

  defp inbound_metrics() do
    [
      Telemetry.Metrics.sum(
        "inbound-rtp.bytes_received_total",
        event_name: @packet_received_event,
        measurement: :bytes
      ),
      Telemetry.Metrics.counter(
        "inbound-rtp.packets_received_total",
        event_name: @packet_received_event
      ),
      Telemetry.Metrics.last_value(
        "inbound-rtp.bytes_received",
        event_name: @inbound_rtp_event,
        measurement: :bytes_received
      ),
      Telemetry.Metrics.last_value(
        "inbound-rtp.packets_received",
        event_name: @inbound_rtp_event,
        measurement: :packets_received
      ),
      Telemetry.Metrics.last_value(
        "inbound-rtp.nack_count",
        event_name: @inbound_rtp_event,
        measurement: :nack_count
      ),
      Telemetry.Metrics.last_value(
        "inbound-rtp.pli_count",
        event_name: @inbound_rtp_event,
        measurement: :pli_count
      ),
      Telemetry.Metrics.last_value(
        "inbound-rtp.markers_received",
        event_name: @inbound_rtp_event,
        measurement: :markers_received
      ),
      Telemetry.Metrics.last_value(
        "inbound-rtp.codec",
        event_name: @inbound_rtp_event,
        measurement: :codec
      )
    ]
  end

  defp outbound_metrics() do
    [
      Telemetry.Metrics.sum(
        "outbound-rtp.bytes_sent_total",
        event_name: @packet_sent_event,
        measurement: :bytes
      ),
      Telemetry.Metrics.counter(
        "outbound-rtp.packets_sent_total",
        event_name: @packet_sent_event
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.bytes_sent",
        event_name: @outbound_rtp_event,
        measurement: :bytes_sent
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.packets_sent",
        event_name: @outbound_rtp_event,
        measurement: :packets_sent
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.nack_count",
        event_name: @outbound_rtp_event,
        measurement: :nack_count
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.pli_count",
        event_name: @outbound_rtp_event,
        measurement: :pli_count
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.markers_sent",
        event_name: @outbound_rtp_event,
        measurement: :markers_sent
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.codec",
        event_name: @outbound_rtp_event,
        measurement: :codec
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.retransmitted_packets_sent",
        event_name: @outbound_rtp_event,
        measurement: :retransmitted_packets_sent
      ),
      Telemetry.Metrics.last_value(
        "outbound-rtp.retransmitted_bytes_sent",
        event_name: @outbound_rtp_event,
        measurement: :retransmitted_bytes_sent
      )
    ]
  end

  defp remote_candidate() do
    [
      Telemetry.Metrics.last_value(
        "remote_candidate.port",
        event_name: @remote_candidate_event,
        measurement: :port
      ),
      Telemetry.Metrics.last_value(
        "remote_candidate.candidate_type",
        event_name: @remote_candidate_event,
        measurement: :candidate_type
      ),
      Telemetry.Metrics.last_value(
        "remote_candidate.address",
        event_name: @remote_candidate_event,
        measurement: :address
      ),
      Telemetry.Metrics.last_value(
        "remote_candidate.protocol",
        event_name: @remote_candidate_event,
        measurement: :protocol
      )
    ]
  end

  @spec emit_inbound_packet_event(
          ExRTP.Packet.t(),
          MediaStreamTrack.id(),
          MediaStreamTrack.rid() | nil,
          TelemetryMetrics.label()
        ) :: :ok
  def emit_inbound_packet_event(packet, webrtc_track_id, rid, telemetry_label) do
    track_label =
      if is_nil(rid) do
        [track_id: webrtc_track_id]
      else
        [track_id: "#{webrtc_track_id}:#{rid}"]
      end

    telemetry_label = telemetry_label ++ track_label

    TelemetryMetrics.execute(
      @packet_received_event,
      %{bytes: byte_size(packet.payload)},
      %{},
      telemetry_label
    )

    :ok
  end

  @spec emit_outbound_packet_event(
          ExRTP.Packet.t(),
          MediaStreamTrack.id(),
          TelemetryMetrics.label()
        ) :: :ok
  def emit_outbound_packet_event(packet, webrtc_track_id, telemetry_label) do
    telemetry_label = telemetry_label ++ [track_id: webrtc_track_id]

    TelemetryMetrics.execute(
      @packet_sent_event,
      %{bytes: byte_size(packet.payload)},
      %{},
      telemetry_label
    )

    :ok
  end

  @spec register_events(TelemetryMetrics.label()) :: :ok
  def register_events(telemetry_label) do
    Enum.each(
      [
        @inbound_rtp_event,
        @packet_received_event,
        @outbound_rtp_event,
        @packet_sent_event
      ],
      &TelemetryMetrics.register(&1, telemetry_label)
    )

    :ok
  end

  @spec emit_from_rtc_stats(rtc_stats_report(), TelemetryMetrics.label()) :: :ok
  def emit_from_rtc_stats(metrics, telemetry_label) do
    Enum.each(metrics, fn {_id, entry} -> handle_entry(entry, telemetry_label) end)
  end

  defp handle_entry(%{type: :inbound_rtp} = entry, telemetry_label) do
    telemetry_label = telemetry_label ++ [track_id: entry[:track_identifier]]

    TelemetryMetrics.execute(
      @inbound_rtp_event,
      Map.take(entry, [
        :packets_received,
        :bytes_received,
        :nack_count,
        :pli_count,
        :markers_received,
        :codec
      ]),
      %{},
      telemetry_label
    )
  end

  defp handle_entry(%{type: :outbound_rtp} = entry, telemetry_label) do
    telemetry_label = telemetry_label ++ [track_id: entry[:track_identifier]]

    TelemetryMetrics.execute(
      @outbound_rtp_event,
      Map.take(entry, [
        :packets_sent,
        :bytes_sent,
        :nack_count,
        :pli_count,
        :markers_sent,
        :codec,
        :retransmitted_packets_sent,
        :retransmitted_bytes_sent
      ]),
      %{},
      telemetry_label
    )
  end

  defp handle_entry(%{type: :remote_candidate} = entry, telemetry_label) do
    telemetry_label = telemetry_label ++ [candidate_id: entry.id]

    TelemetryMetrics.execute(
      @remote_candidate_event,
      entry,
      %{},
      telemetry_label
    )
  end

  defp handle_entry(_entry, _label), do: :ok
end
