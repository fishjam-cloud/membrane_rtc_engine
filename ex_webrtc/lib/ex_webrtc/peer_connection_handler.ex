defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.PeerConnectionHandler do
  @moduledoc false
  use Membrane.Endpoint

  require Membrane.Logger

  alias Membrane.Buffer
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC, as: EndpointExWebRTC
  alias Membrane.RTC.Engine.Track

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, RTPReceiver, RTPTransceiver}

  def_options endpoint_id: [
                spec: String.t(),
                description: "ID of the parent endpoint"
              ],
              ice_port_range: [
                spec: Enumerable.t(non_neg_integer()),
                description: "Range of ports that ICE will use for gathering host candidates."
              ],
              video_codecs: [
                spec: [EndpointExWebRTC.video_codec()] | nil,
                description: "Allowed video codecs"
              ],
              ice_servers: [
                spec: [PeerConnection.Configuration.ice_server()],
                description: "List of servers that may be used by ICE agent",
                default: []
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

  defmodule InboundTrack do
    @moduledoc false

    @enforce_keys [:track_id, :simulcast?]
    defstruct @enforce_keys

    @type t() :: %__MODULE__{track_id: Track.id(), simulcast?: boolean()}
  end

  @impl true
  def handle_init(_ctx, opts) do
    %{endpoint_id: endpoint_id} = opts

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
        ice_port_range: opts.ice_port_range,
        ice_servers: opts.ice_servers,
        video_codecs: video_codecs,
        controlling_process: self()
      ]

    peer_connection = {:via, Registry, {Membrane.RTC.Engine.Registry.PeerConnection, endpoint_id}}
    pc_gen_server_options = [name: peer_connection]

    child_spec = %{
      id: :peer_connection,
      start: {PeerConnection, :start_link, [pc_options, pc_gen_server_options]}
    }

    {:ok, _sup} = Supervisor.start_link([child_spec], strategy: :one_for_one)

    state = %{
      pc: peer_connection,
      endpoint_id: endpoint_id,
      # maps track_id to webrtc_track_id
      outbound_tracks: %{},
      # maps webrtc_track_id to InboundTrack
      inbound_tracks: %{},
      mid_to_track_id: %{},
      track_id_to_metadata: %{}
    }

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {_track_id, _variant}) = pad, _ctx, state) do
    {[stream_format: {pad, %Membrane.RTP{}}], state}
  end

  @impl true
  def handle_pad_added(_pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(Pad.ref(:input, track_id), buffer, _ctx, state)
      when is_map_key(state.outbound_tracks, track_id) do
    %Buffer{
      pts: timestamp,
      payload: payload,
      metadata: %{rtp: rtp}
    } = buffer

    webrtc_track_id = Map.fetch!(state.outbound_tracks, track_id)

    packet =
      ExRTP.Packet.new(
        payload,
        payload_type: rtp.payload_type,
        sequence_number: rtp.sequence_number,
        timestamp: timestamp,
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
    Membrane.Logger.warning("Received buffer from unknown track #{track_id}")
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

    {answer_action ++ tracks_action ++ tracks_removed_action, state}
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

    removed_mids =
      Enum.map(webrtc_track_ids, fn webrtc_track_id ->
        transceiver =
          Enum.find(
            transceivers,
            &(not is_nil(&1.sender.track) and &1.sender.track.id == webrtc_track_id)
          )

        :ok = PeerConnection.remove_track(state.pc, transceiver.sender.id)
        transceiver.mid
      end)

    state = update_in(state.outbound_tracks, &Map.drop(&1, track_ids))
    state = update_in(state.mid_to_track_id, &Map.drop(&1, removed_mids))
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

  defp handle_webrtc_msg({:ice_candidate, candidate}, _ctx, state) do
    msg = {:candidate, candidate}
    {[notify_parent: msg], state}
  end

  defp handle_webrtc_msg({:track, _track}, _ctx, state) do
    raise("We do not expect to receive any tracks")
    {[], state}
  end

  defp handle_webrtc_msg({:rtp, webrtc_track_id, rid, packet}, ctx, state) do
    variant = EndpointExWebRTC.to_track_variant(rid)

    actions =
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

        [buffer: {pad, buffer}]
      else
        _other -> []
      end

    {actions, state}
  end

  defp handle_webrtc_msg({:signaling_state_change, :stable}, _ctx, state) do
    {[notify_parent: :negotiation_done], state}
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
    Membrane.Logger.debug("Unexpected message from webrtc: #{inspect(msg)}")
    {[], state}
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

      Membrane.Logger.info(
        "track #{track.id}, #{track.kind} added on transceiver #{transceiver.id}"
      )

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
    do_receive_new_tracks([]) |> make_tracks(state)
  end

  defp do_receive_new_tracks(acc) do
    receive do
      {:ex_webrtc, pc, {:track, track}} ->
        transceiver =
          PeerConnection.get_transceivers(pc)
          |> Enum.find(fn transceiver ->
            not is_nil(transceiver.receiver.track) and
              transceiver.receiver.track.id == track.id
          end)

        Membrane.Logger.info("new track #{track.id}, #{track.kind}")

        if is_nil(transceiver) do
          transceivers = PeerConnection.get_transceivers(pc)

          Logger.error(
            "No transceiver for incoming track #{track.id}, #{track.kind}, transceivers: #{inspect(transceivers)}. \
            This is likely caused by incompatible codecs"
          )

          do_receive_new_tracks(acc)
        else
          PeerConnection.set_transceiver_direction(pc, transceiver.id, :sendrecv)

          PeerConnection.replace_track(
            pc,
            transceiver.sender.id,
            MediaStreamTrack.new(track.kind)
          )

          PeerConnection.set_transceiver_direction(pc, transceiver.id, :recvonly)
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

    simulcast? = not is_nil(track.rids)

    variants =
      if simulcast?, do: Enum.map(track.rids, &EndpointExWebRTC.to_track_variant/1), else: [:high]

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

    new_inbound_track = %InboundTrack{track_id: track_id, simulcast?: simulcast?}

    state = update_in(state.inbound_tracks, &Map.put(&1, rtc_track_id, new_inbound_track))
    do_make_tracks(tracks, transceivers, state, [engine_track | acc])
  end
end
