defmodule Membrane.RTC.Engine.Endpoint.Forwarder.PeerConnectionHandler do
  @moduledoc false
  use Membrane.Sink

  require Membrane.Logger

  alias ExWebRTC.{MediaStreamTrack, PeerConnection}

  @ice_headers [
    {"Content-Type", "application/trickle-ice-sdpfrag"}
  ]

  def_options endpoint_id: [
                spec: String.t(),
                description: "Pid of parent Engine"
              ],
              telemetry_label: [
                spec: Membrane.TelemetryMetrics.label(),
                default: [],
                description: "Label passed to Membrane.TelemetryMetrics functions"
              ],
              broadcaster_url: [
                spec: String.t(),
                description: "Address under which broadcaster is spawned"
              ],
              broadcaster_token: [
                spec: String.t(),
                description: "Token allowing for streaming into broadcaster"
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request

  @impl true
  def handle_init(_ctx, opts) do
    pc = spawn_peer_connection()

    state =
      Map.merge(opts, %{
        pc: pc,
        tracks: %{},
        candidates: [],
        patch_endpoint: nil,
        connection_state: nil,
        peer_connection_signaling_state: nil
      })

    {[], state}
  end

  @impl true
  def handle_buffer(Pad.ref(:input, track_id), buffer, _ctx, state) do
    webrtc_track = Map.fetch!(state.tracks, track_id)
    packet = to_webrtc_packet(buffer)

    :ok = PeerConnection.send_rtp(state.pc, webrtc_track.id, packet)

    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    if Process.alive?(state.pc), do: PeerConnection.close(state.pc)

    {[terminate: :normal], state}
  end

  @impl true
  def handle_parent_notification({:start_negotiation, tracks}, _ctx, state) do
    video_track = MediaStreamTrack.new(:video, [tracks.video.stream_id])
    audio_track = MediaStreamTrack.new(:audio, [tracks.audio.stream_id])

    {:ok, video_tr} = PeerConnection.add_transceiver(state.pc, video_track, direction: :sendonly)
    {:ok, _tr} = PeerConnection.add_transceiver(state.pc, audio_track, direction: :sendonly)

    {:ok, offer} = PeerConnection.create_offer(state.pc)
    :ok = PeerConnection.set_local_description(state.pc, offer)

    url = state.broadcaster_url |> URI.merge("/api/whip") |> to_string()
    headers = sdp_headers(state.broadcaster_token)

    case HTTPoison.post(url, offer.sdp, headers) do
      {:ok, %{status_code: 201} = response} ->
        Membrane.Logger.debug("Successfully sent SDP offer : #{inspect(offer.sdp)}")

        {"location", patch_endpoint} =
          Enum.find(response.headers, fn {key, _value} -> key == "location" end)

        answer = %ExWebRTC.SessionDescription{type: :answer, sdp: response.body}
        :ok = PeerConnection.set_remote_description(state.pc, answer)

        video_codec =
          Enum.find(video_tr.codecs, &(&1.mime_type == to_mime_type(tracks.video.encoding)))

        :ok = PeerConnection.set_sender_codec(state.pc, video_tr.sender.id, video_codec)

        {[],
         %{
           state
           | patch_endpoint: patch_endpoint,
             tracks: %{tracks.video.id => video_track, tracks.audio.id => audio_track}
         }}

      {:ok, response} ->
        Membrane.Logger.error("Failed to exchange SDP, status: #{response.status_code}")
        {[terminate: {:crash, {:broadcaster_response, response.status_code}}], state}

      {:error, error} ->
        Membrane.Logger.error("Failed to send SDP offer, reason: #{inspect(error.reason)}")
        {[terminate: {:crash, error.reason}], state}
    end
  end

  @impl true
  def handle_info(
        {:ex_webrtc, _pc, {:ice_candidate, candidate}},
        _ctx,
        %{patch_endpoint: nil} = state
      ) do
    {[], %{state | candidates: state.candidates ++ [candidate]}}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, _ctx, state) do
    for c <- state.candidates ++ [candidate] do
      body = c |> ExWebRTC.ICECandidate.to_json() |> Jason.encode!()
      url = state.broadcaster_url |> URI.merge(state.patch_endpoint) |> to_string()

      case HTTPoison.patch(url, body, @ice_headers) do
        {:ok, %{status_code: 204}} ->
          Membrane.Logger.debug("Successfully sent ICE candidate: #{inspect(c)}")

        {:ok, response} ->
          Membrane.Logger.error(
            "Failed to send ICE, status: #{response.status_code}, candidate: #{inspect(c)}"
          )

        {:error, error} ->
          Membrane.Logger.error("Failed to send ICE, reason: #{error.reason}")
      end
    end

    {[], %{state | candidates: []}}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:connection_state_change, connection_state}}, _ctx, state) do
    actions =
      case {connection_state, state.peer_connection_signaling_state} do
        {:connected, :stable} -> [notify_parent: :negotiation_done]
        _other -> []
      end

    {actions, %{state | connection_state: connection_state}}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:signaling_state_change, new_state}}, _ctx, state) do
    actions =
      case {state.peer_connection_signaling_state, new_state, state.connection_state} do
        {:have_remote_offer, :stable, :connected} -> [notify_parent: :negotiation_done]
        _other -> []
      end

    {actions, %{state | peer_connection_signaling_state: new_state}}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:rtcp, packets}}, _ctx, state) do
    actions =
      packets
      |> Enum.map(&maybe_pli_event(&1, state))
      |> Enum.filter(& &1)

    {actions, state}
  end

  def handle_info({:ex_webrtc, _pc, msg}, _ctx, state) do
    Membrane.Logger.debug("Ignoring message from peer connection: #{inspect(msg)}")
    {[], state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pc, reason}, _ctx, %{pc: pc} = state) do
    case reason do
      :normal ->
        # Reason normal means that `PeerConnection.close` function was invoked
        # This is unexpected because PeerConnection is only closed on termination
        Membrane.Logger.error("PeerConnection unexpectedly closed with reason: :normal")
        {[terminate: {:crash, :peer_connection_closed}], state}

      {:shutdown, reason} ->
        Membrane.Logger.error(
          "PeerConnection unexpectedly closed with reason: #{inspect(reason)}"
        )

        {[terminate: {:crash, reason}], state}

      reason ->
        Membrane.Logger.error("PeerConnection crashed with reason: #{inspect(reason)}")
        {[terminate: reason], state}
    end
  end

  defp spawn_peer_connection() do
    {:ok, pc} =
      [
        ice_port_range: Application.get_env(:membrane_rtc_engine_ex_webrtc, :ice_port_range),
        ice_servers: Application.get_env(:membrane_rtc_engine_ex_webrtc, :ice_servers),
        controlling_process: self()
      ]
      |> Enum.filter(fn {_k, v} -> not is_nil(v) end)
      |> PeerConnection.start()

    Process.monitor(pc)

    pc
  end

  defp maybe_pli_event({webrtc_track_id, %ExRTCP.Packet.PayloadFeedback.PLI{}}, state) do
    case find_track_id(state.tracks, webrtc_track_id) do
      {:ok, track_id} ->
        Membrane.Logger.debug("Received keyframe request for track #{track_id}")
        {:event, {Pad.ref(:input, track_id), %Membrane.KeyframeRequestEvent{}}}

      :error ->
        Membrane.Logger.warning(
          "Received keyframe request for unknown webrtc track #{webrtc_track_id}"
        )
    end
  end

  defp maybe_pli_event(_packet, _state), do: nil

  defp to_webrtc_packet(buffer) do
    rtp = buffer.metadata.rtp

    packet =
      ExRTP.Packet.new(
        buffer.payload,
        payload_type: rtp.payload_type,
        sequence_number: rtp.sequence_number,
        timestamp: rtp.timestamp,
        ssrc: rtp.ssrc,
        csrc: Map.get(rtp, :csrc, []),
        marker: rtp.marker,
        padding: Map.get(rtp, :padding_size, 0)
      )

    extensions = rtp.extensions || []

    Enum.reduce(extensions, packet, fn extension, packet ->
      ExRTP.Packet.add_extension(packet, extension)
    end)
  end

  defp find_track_id(tracks, webrtc_track_id) do
    case Enum.find(tracks, fn {_track_id, webrtc_track} -> webrtc_track.id == webrtc_track_id end) do
      {track_id, _webrtc_track_id} -> {:ok, track_id}
      nil -> :error
    end
  end

  defp sdp_headers(token) do
    [
      {"Accept", "application/sdp"},
      {"Content-Type", "application/sdp"},
      {"Authorization", "Bearer #{token}"}
    ]
  end

  defp to_mime_type(:VP8), do: "video/VP8"
  defp to_mime_type(:H264), do: "video/H264"
end
