defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.PeerConnectionHandler do
  @moduledoc false
  use Membrane.Endpoint

  require Membrane.Logger

  alias Membrane.Buffer
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC, as: EndpointExWebRTC
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.Metrics
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.PeerConnectionHandler.InboundTrack
  alias Membrane.RTC.Engine.Track

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, RTPReceiver, RTPTransceiver}

  def_options endpoint_id: [
                spec: String.t(),
                description: "ID of the parent endpoint"
              ],
              video_codecs: [
                spec: [EndpointExWebRTC.video_codec()] | nil,
                description: "Allowed video codecs"
              ],
              telemetry_label: [
                spec: Keyword.t(),
                default: [],
                description: "Label passed to Membrane.TelemetryMetrics functions"
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request,
    flow_control: :push

  @video_codecs [
    H264: %ExWebRTC.RTPCodecParameters{
      payload_type: 98,
      mime_type: "video/H264",
      clock_rate: 90_000
    },
    VP8: %ExWebRTC.RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/VP8",
      clock_rate: 90_000,
      channels: nil,
      sdp_fmtp_line: nil,
      rtcp_fbs: []
    }
  ]

  @audio_level_uri "urn:ietf:params:rtp-hdrext:ssrc-audio-level"

  @impl true
  def handle_init(_ctx, opts) do
    video_codecs =
      if opts.video_codecs do
        Enum.filter(@video_codecs, fn {codec, _params} ->
          codec in opts.video_codecs
        end)
      else
        @video_codecs
      end
      |> Enum.map(fn {_codec, params} -> params end)

    pc_options =
      [
        ice_port_range: Application.get_env(:membrane_rtc_engine_ex_webrtc, :ice_port_range),
        ice_servers: Application.get_env(:membrane_rtc_engine_ex_webrtc, :ice_servers),
        video_codecs: video_codecs,
        controlling_process: self(),
        rtp_header_extensions:
          PeerConnection.Configuration.default_rtp_header_extensions() ++
            [%{type: :audio, uri: @audio_level_uri}]
      ]
      |> Enum.filter(fn {_k, v} -> not is_nil(v) end)

    {:ok, pc} = PeerConnection.start(pc_options)
    Process.monitor(pc)

    state = %{
      pc: pc,
      endpoint_id: opts.endpoint_id,
      # maps track_id to webrtc_track_id
      outbound_tracks: %{},
      # maps webrtc_track_id to InboundTrack
      inbound_tracks: %{},
      mid_to_track_id: %{},
      track_id_to_metadata: %{},
      telemetry_label: opts.telemetry_label,
      get_stats_interval:
        Application.get_env(:membrane_rtc_engine_ex_webrtc, :get_stats_interval),
      peer_connection_signaling_state: nil,
      connection_state: nil,
      prev_transport_stats: nil
    }

    if not is_nil(state.get_stats_interval),
      do: Process.send_after(self(), :get_stats, state.get_stats_interval)

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {track_id, variant}) = pad, _ctx, state) do
    {webrtc_track_id, _inbound_track} =
      Enum.find(state.inbound_tracks, fn {_id, track} -> track.track_id == track_id end)

    state =
      update_in(
        state,
        [:inbound_tracks, webrtc_track_id],
        &InboundTrack.update_variant_state(&1, variant, :linked)
      )

    {[stream_format: {pad, %Membrane.RTP{}}], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, track_id), _ctx, state) do
    if not is_map_key(state.outbound_tracks, track_id),
      do: Membrane.Logger.error("Receiving new unknown track: #{track_id}")

    {[], state}
  end

  @impl true
  def handle_buffer(Pad.ref(:input, track_id), buffer, _ctx, state)
      when is_map_key(state.outbound_tracks, track_id) do
    %Buffer{
      payload: payload,
      metadata: %{rtp: rtp}
    } = buffer

    webrtc_track_id = Map.fetch!(state.outbound_tracks, track_id)

    packet =
      ExRTP.Packet.new(
        payload,
        payload_type: rtp.payload_type,
        sequence_number: rtp.sequence_number,
        timestamp: rtp.timestamp,
        ssrc: rtp.ssrc,
        csrc: rtp.csrc,
        marker: rtp.marker,
        padding: rtp.padding_size
      )

    extensions = if is_list(rtp.extensions), do: rtp.extensions, else: []

    packet =
      Enum.reduce(extensions, packet, fn extension, packet ->
        ExRTP.Packet.add_extension(packet, extension)
      end)

    :ok = PeerConnection.send_rtp(state.pc, webrtc_track_id, packet)

    {[], state}
  end

  @impl true
  def handle_buffer(Pad.ref(:input, track_id), _buffer, _ctx, state) do
    Membrane.Logger.debug("Received buffer from unknown track #{track_id}")
    {[], state}
  end

  @impl true
  def handle_parent_notification({:offer, event, new_outbound_tracks}, _ctx, state) do
    %{sdp_offer: offer, mid_to_track_id: mid_to_track_id} = event

    state = update_in(state.mid_to_track_id, &Map.merge(&1, mid_to_track_id))

    track_id_to_metadata = Map.get(event, :track_id_to_track_metadata, %{})
    state = Map.put(state, :track_id_to_metadata, track_id_to_metadata)

    :ok = PeerConnection.set_remote_description(state.pc, offer)

    state = add_new_tracks_to_webrtc(state, new_outbound_tracks)

    {:ok, answer} = PeerConnection.create_answer(state.pc)
    :ok = PeerConnection.set_local_description(state.pc, answer)

    {tracks, state} = receive_new_tracks_from_webrtc(state)

    answer_action = [
      notify_parent: {:answer, answer, state.mid_to_track_id}
    ]

    tracks_action = if Enum.empty?(tracks), do: [], else: [notify_parent: {:new_tracks, tracks}]
    {tracks_removed_action, state} = get_tracks_removed_action(state)

    {answer_action ++ tracks_removed_action ++ tracks_action, state}
  end

  @impl true
  def handle_parent_notification({:candidate, candidate}, _ctx, state) do
    :ok = PeerConnection.add_ice_candidate(state.pc, candidate)

    {[], state}
  end

  @impl true
  def handle_parent_notification({:tracks_removed, track_ids}, _ctx, state) do
    # TODO: properly remove tracks by either removing the transceiver or reusing
    # transceivers from removed tracks
    webrtc_track_ids = Enum.map(track_ids, &Map.fetch!(state.outbound_tracks, &1))

    transceivers = PeerConnection.get_transceivers(state.pc)

    Enum.each(webrtc_track_ids, fn webrtc_track_id ->
      transceiver =
        Enum.find(
          transceivers,
          &(not is_nil(&1.sender.track) and &1.sender.track.id == webrtc_track_id)
        )

      if not is_nil(transceiver) do
        :ok = PeerConnection.remove_track(state.pc, transceiver.sender.id)
      end
    end)

    state = update_in(state.outbound_tracks, &Map.drop(&1, track_ids))

    state =
      update_in(
        state.mid_to_track_id,
        fn mid_to_track ->
          mid_to_track
          |> Enum.filter(fn {_mid, id} -> id not in track_ids end)
          |> Map.new()
        end
      )

    {[], state}
  end

  @impl true
  def handle_parent_notification({:set_metadata, display_name}, _ctx, state) do
    Logger.metadata(peer: display_name)
    {[], state}
  end

  @impl true
  def handle_parent_notification(msg, _ctx, state) do
    Membrane.Logger.error("Unexpected parent notification: #{inspect(msg)}")
    {[], state}
  end

  @impl true
  def handle_event(
        Pad.ref(:output, {track_id, variant}),
        %Membrane.KeyframeRequestEvent{},
        _ctx,
        state
      ) do
    {rtc_track_id, inbound_track} =
      Enum.find(state.inbound_tracks, fn {_rtc_track_id, track} ->
        track.track_id == track_id
      end)

    rid = if inbound_track.simulcast?, do: EndpointExWebRTC.to_rid(variant), else: nil
    PeerConnection.send_pli(state.pc, rtc_track_id, rid)

    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, msg}, ctx, state) do
    handle_webrtc_msg(msg, ctx, state)
  end

  @impl true
  def handle_info(:get_stats, _ctx, state) do
    transport_stats =
      state.pc
      |> PeerConnection.get_stats()
      |> Metrics.emit_transport_event(state.telemetry_label, state.prev_transport_stats)

    Process.send_after(self(), :get_stats, state.get_stats_interval)

    {[], %{state | prev_transport_stats: transport_stats}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pc, reason}, _ctx, %{pc: pc} = state) do
    case reason do
      {:shutdown, :peer_closed_for_writing} ->
        Membrane.Logger.debug(
          "PeerConnection closed on client side. ExWebrtc reason: #{inspect(reason)}"
        )

        {[terminate: :normal], state}

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

    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    if Process.alive?(state.pc), do: PeerConnection.close(state.pc)

    {[terminate: :normal], state}
  end

  defp handle_webrtc_msg({:ice_candidate, candidate}, _ctx, state) do
    msg = {:candidate, candidate}
    {[notify_parent: msg], state}
  end

  defp handle_webrtc_msg({:track, _track}, _ctx, state) do
    raise("We do not expect to receive any tracks")
    {[], state}
  end

  defp handle_webrtc_msg({:rtp, webrtc_track_id, rid, _packet} = msg, ctx, state) do
    variant = EndpointExWebRTC.to_track_variant(rid)

    case Map.get(state.inbound_tracks, webrtc_track_id) do
      %InboundTrack{variants: %{^variant => :new}} = track ->
        state =
          update_in(
            state,
            [:inbound_tracks, webrtc_track_id],
            &InboundTrack.update_variant_state(&1, variant, :ready)
          )

        {[
           notify_parent: {:track_ready, track.track_id, variant, track.encoding}
         ], state}

      %InboundTrack{variants: %{^variant => :ready}} ->
        {[], state}

      %InboundTrack{variants: %{^variant => :linked}} ->
        forward_inbound_packet(msg, ctx, state)

      _other ->
        {[], state}
    end
  end

  defp handle_webrtc_msg({:connection_state_change, :failed}, _ctx, state) do
    Membrane.Logger.warning("Peer connection failed. #{inspect(state)}")
    {[], state}
  end

  defp handle_webrtc_msg({:connection_state_change, connection_state}, _ctx, state) do
    actions =
      case {connection_state, state.peer_connection_signaling_state, empty_connection?(state.pc)} do
        {:connected, :stable, false} -> [notify_parent: :negotiation_done]
        _other -> []
      end

    {actions, %{state | connection_state: connection_state}}
  end

  defp handle_webrtc_msg({:signaling_state_change, new_state}, _ctx, state) do
    actions =
      case {state.peer_connection_signaling_state, new_state} do
        {:have_remote_offer, :stable} ->
          # `:negotiation_done` should be sent when `:signaling_state` is stable and `:connection_state` is connected
          # but there is an egde case when an empty sdp is sent or no tracks are accepted
          # then PeerConnection will never connect to the other peer so we have to return `:negotiation_done` immediatelly
          if state.connection_state == :connected || empty_connection?(state.pc),
            do: [notify_parent: :negotiation_done],
            else: []

        _other ->
          []
      end

    {actions, %{state | peer_connection_signaling_state: new_state}}
  end

  defp handle_webrtc_msg({:rtcp, packets}, _ctx, state) do
    actions =
      Enum.flat_map(packets, fn
        {webrtc_track_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} ->
          pli_event(webrtc_track_id, state)

        {_track_id, _other} ->
          []
      end)

    {actions, state}
  end

  defp handle_webrtc_msg(msg, _ctx, state) do
    Membrane.Logger.debug("Ignoring message from webrtc: #{inspect(msg)}")
    {[], state}
  end

  defp forward_inbound_packet({:rtp, webrtc_track_id, rid, packet}, ctx, state) do
    variant = EndpointExWebRTC.to_track_variant(rid)

    with {:ok, inbound_track} <- Map.fetch(state.inbound_tracks, webrtc_track_id),
         pad <- Pad.ref(:output, {inbound_track.track_id, variant}),
         true <- Map.has_key?(ctx.pads, pad) do
      rtp =
        packet
        |> Map.from_struct()
        |> Map.take([
          :csrc,
          :extensions,
          :marker,
          :padding_size,
          :payload_type,
          :sequence_number,
          :ssrc,
          :timestamp
        ])

      buffer = %Buffer{
        pts: packet.timestamp,
        payload: packet.payload,
        metadata: %{rtp: rtp}
      }

      {action, inbound_track} = InboundTrack.maybe_update_vad(inbound_track, pad, packet)
      state = put_in(state, [:inbound_tracks, webrtc_track_id], inbound_track)

      {action ++ [buffer: {pad, buffer}], state}
    else
      _other -> {[], state}
    end
  end

  defp pli_event(webrtc_track_id, state) do
    outbound_track =
      Enum.find(state.outbound_tracks, fn {_track_id, id} -> id == webrtc_track_id end)

    case outbound_track do
      {track_id, _rtc_track_id} ->
        Membrane.Logger.debug("PLI event for track: #{track_id}")
        pad = Pad.ref(:input, track_id)
        [event: {pad, %Membrane.KeyframeRequestEvent{}}]

      nil ->
        Membrane.Logger.warning("Received PLI for unknown track #{webrtc_track_id}")
        []
    end
  end

  defp add_new_tracks_to_webrtc(state, new_outbound_tracks)
       when map_size(new_outbound_tracks) == 0,
       do: state

  defp add_new_tracks_to_webrtc(state, new_outbound_tracks) do
    outbound_transceivers =
      state.pc
      |> PeerConnection.get_transceivers()
      |> Enum.filter(fn transceiver ->
        transceiver.current_direction == nil and
          not Map.has_key?(state.mid_to_track_id, transceiver.mid)
      end)

    {new_track_ids, _transceivers} =
      new_outbound_tracks
      |> Enum.flat_map_reduce(
        outbound_transceivers,
        fn {_track_id, engine_track}, outbound_transceivers ->
          add_track(state, engine_track, outbound_transceivers)
        end
      )

    {new_mid_to_track_id, new_outbound_tracks} =
      new_track_ids
      |> Enum.reduce({%{}, %{}}, fn {track_id, webrtc_track_id, mid}, {mids, tracks} ->
        {Map.put(mids, mid, track_id), Map.put(tracks, track_id, webrtc_track_id)}
      end)

    state = update_in(state.mid_to_track_id, &Map.merge(&1, new_mid_to_track_id))
    state = update_in(state.outbound_tracks, &Map.merge(&1, new_outbound_tracks))

    state
  end

  defp add_track(state, engine_track, outbound_transceivers) do
    track = MediaStreamTrack.new(engine_track.type, [engine_track.stream_id])

    transceiver =
      Enum.find(outbound_transceivers, fn transceiver ->
        transceiver.kind == track.kind
      end)

    if transceiver do
      PeerConnection.set_transceiver_direction(state.pc, transceiver.id, :sendonly)
      PeerConnection.replace_track(state.pc, transceiver.sender.id, track)

      outbound_transceivers = List.delete(outbound_transceivers, transceiver)

      Membrane.Logger.info("track #{inspect(track)} added on transceiver #{transceiver.id}")

      {[{engine_track.id, track.id, transceiver.mid}], outbound_transceivers}
    else
      Membrane.Logger.error("Couldn't find transceiver for track #{engine_track.id}")
      {[], outbound_transceivers}
    end
  end

  defp get_tracks_removed_action(state) do
    transceivers = PeerConnection.get_transceivers(state.pc)

    {removed_tracks, removed_mids} =
      transceivers
      |> Enum.filter(fn transceiver ->
        transceiver.current_direction == :inactive and
          Map.has_key?(state.inbound_tracks, transceiver.receiver.track.id)
      end)
      |> Enum.reduce({[], []}, fn transceiver, {removed_tracks, removed_mids} ->
        {[transceiver.receiver.track.id | removed_tracks], [transceiver.mid | removed_mids]}
      end)

    if Enum.empty?(removed_tracks) do
      {[], state}
    else
      removed_track_ids =
        Enum.map(removed_tracks, &Map.get(state.inbound_tracks, &1).track_id)

      inbound_tracks = Map.drop(state.inbound_tracks, removed_tracks)
      mid_to_track_id = Map.drop(state.mid_to_track_id, removed_mids)

      {[notify_parent: {:tracks_removed, removed_track_ids}],
       %{state | inbound_tracks: inbound_tracks, mid_to_track_id: mid_to_track_id}}
    end
  end

  defp receive_new_tracks_from_webrtc(state) do
    []
    |> do_receive_new_tracks()
    |> make_tracks(state)
  end

  defp do_receive_new_tracks(acc) do
    receive do
      {:ex_webrtc, pc, {:track, track}} ->
        transceivers = PeerConnection.get_transceivers(pc)

        track_transceiver =
          Enum.find(transceivers, &(&1.receiver.track.id == track.id))

        Membrane.Logger.info("new track #{inspect(track)}")

        if is_nil(track_transceiver) do
          Logger.warning(
            "No transceiver for incoming track #{track.id}, #{track.kind}, transceivers: #{inspect(transceivers)}. \
            This is likely either caused by incompatible codecs or attempts to use video in an audio-only room"
          )

          do_receive_new_tracks(acc)
        else
          do_receive_new_tracks([track | acc])
        end
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp make_tracks(tracks, state) do
    transceivers = PeerConnection.get_transceivers(state.pc)
    do_make_tracks(tracks, transceivers, state, [])
  end

  defp do_make_tracks([], _transceivers, state, acc), do: {Enum.reverse(acc), state}

  defp do_make_tracks([track | tracks], transceivers, state, acc) do
    {codec, mid} =
      Enum.find_value(transceivers, fn
        %RTPTransceiver{receiver: %RTPReceiver{track: ^track, codec: codec}, mid: mid} ->
          {codec, mid}

        _other ->
          nil
      end)

    %MediaStreamTrack{id: rtc_track_id, kind: kind} = track

    encoding =
      case codec.mime_type do
        "audio/opus" -> :OPUS
        "video/VP8" -> :VP8
        "video/H264" -> :H264
      end

    track_id = Map.fetch!(state.mid_to_track_id, mid)

    track_already_exists? =
      state.inbound_tracks
      |> Map.values()
      |> Enum.find(&(&1.track_id == track_id))

    if track_already_exists? do
      Membrane.Logger.error(
        "Engine track with id #{track_id} was already added. This track will be ignored otherwise it would cause engine crash. \
        WebRTC Track: #{inspect(track)}, with mid: #{mid}"
      )

      do_make_tracks(tracks, transceivers, state, acc)
    else
      simulcast? = not is_nil(track.rids)

      variants =
        if simulcast?,
          do: Enum.map(track.rids, &EndpointExWebRTC.to_track_variant/1),
          else: [:high]

      engine_track =
        Track.new(
          kind,
          MediaStreamTrack.generate_stream_id(),
          state.endpoint_id,
          encoding,
          codec.clock_rate,
          codec.sdp_fmtp_line,
          id: track_id,
          metadata: Map.get(state.track_id_to_metadata, track_id),
          variants: variants
        )

      new_inbound_track = InboundTrack.init(track_id, track, encoding, vad_extension(state))

      state = update_in(state.inbound_tracks, &Map.put(&1, rtc_track_id, new_inbound_track))

      do_make_tracks(tracks, transceivers, state, [engine_track | acc])
    end
  end

  defp vad_extension(state) do
    audio_extensions = ExWebRTC.PeerConnection.get_configuration(state.pc).audio_extensions
    Enum.find(audio_extensions, &(&1.uri == @audio_level_uri))
  end

  defp empty_connection?(pc) do
    pc
    |> PeerConnection.get_transceivers()
    |> Enum.all?(&(&1.direction == :inactive || &1.direction == :stopped))
  end
end
