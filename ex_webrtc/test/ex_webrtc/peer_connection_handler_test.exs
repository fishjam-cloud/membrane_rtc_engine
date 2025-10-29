defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.PeerConnectionHandlerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription}

  alias Membrane.Testing.Pipeline

  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.PeerConnectionHandler
  alias Membrane.RTC.Engine.Track

  @endpoint_id "ex_webrtc_endpoint"
  @track_metadata %{"server" => %{"displayName" => "mrwebrtc"}, "peer" => %{}}

  @vp8_codec %ExWebRTC.RTPCodecParameters{
    payload_type: 96,
    mime_type: "video/VP8",
    clock_rate: 90_000,
    channels: nil,
    sdp_fmtp_line: nil,
    rtcp_fbs: []
  }

  setup do
    {:ok, pc} = PeerConnection.start_link()

    %{pc: pc}
  end

  test "peer adds single video track", %{pc: pc} do
    pipeline = start_pipeline()
    track_id = UUID.uuid4()
    mid_to_track_id = %{"0" => track_id}
    track_id_to_metadata = %{track_id => @track_metadata}
    track = MediaStreamTrack.new(:video, [MediaStreamTrack.generate_stream_id()])
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, track, direction: :sendonly)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    media_event = sdp_offer(offer, mid_to_track_id, track_id_to_metadata)

    outbound_tracks = %{}
    Pipeline.notify_child(pipeline, :handler, {:offer, media_event, outbound_tracks})

    assert_pipeline_notified(
      pipeline,
      :handler,
      {:answer, %{type: :answer, sdp: _sdp} = answer, _new_mid_to_track_id}
    )

    assert_pipeline_notified(pipeline, :handler, {:new_tracks, tracks})

    [engine_track] = tracks

    assert %{
             id: ^track_id,
             type: :video,
             origin: @endpoint_id,
             encoding: :VP8,
             variants: [:high],
             metadata: @track_metadata
           } =
             engine_track

    PeerConnection.set_remote_description(pc, answer)
    connect_peer_connection(pipeline, pc)

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)

    [transceiver] = PeerConnection.get_transceivers(pc)
    assert transceiver.current_direction == :sendonly
  end

  test "connection handler adds single track", %{pc: pc} do
    pipeline = start_pipeline()
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, :video, direction: :recvonly)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    media_event = sdp_offer(offer)

    track = engine_video_track()
    outbound_tracks = %{track.id => track}
    Pipeline.notify_child(pipeline, :handler, {:offer, media_event, outbound_tracks})

    assert_pipeline_notified(
      pipeline,
      :handler,
      {:answer, %{type: :answer, sdp: _sdp} = answer, new_mid_to_track_id}
    )

    refute_pipeline_notified(pipeline, :handler, {:new_tracks, _tracks})

    PeerConnection.set_remote_description(pc, answer)
    connect_peer_connection(pipeline, pc)

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)

    [{track_mid, track_id}] = Map.to_list(new_mid_to_track_id)

    [transceiver] = PeerConnection.get_transceivers(pc)
    assert transceiver.current_direction == :recvonly
    assert transceiver.mid == track_mid
    assert track_id == track.id
  end

  test "peer adds audio and video tracks", %{pc: pc} do
    pipeline = start_pipeline()

    video_track_id = UUID.uuid4()
    audio_track_id = UUID.uuid4()
    video_track = MediaStreamTrack.new(:video, [MediaStreamTrack.generate_stream_id()])
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, video_track, direction: :sendonly)
    audio_track = MediaStreamTrack.new(:audio, [MediaStreamTrack.generate_stream_id()])
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, audio_track, direction: :sendonly)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    mid_to_track_id = %{"0" => video_track_id, "1" => audio_track_id}
    Pipeline.notify_child(pipeline, :handler, {:offer, sdp_offer(offer, mid_to_track_id), %{}})

    assert_pipeline_notified(
      pipeline,
      :handler,
      {:answer, %{type: :answer, sdp: _sdp} = answer, _new_mid_to_track_id}
    )

    PeerConnection.set_remote_description(pc, answer)
    connect_peer_connection(pipeline, pc)

    assert_pipeline_notified(pipeline, :handler, {:new_tracks, tracks})

    assert length(tracks) == 2
    engine_audio_track = Enum.find(tracks, &(&1.type == :audio))
    engine_video_track = Enum.find(tracks, &(&1.type == :video))

    assert %{
             id: ^video_track_id,
             type: :video,
             origin: @endpoint_id,
             encoding: :VP8,
             variants: [:high]
           } = engine_video_track

    assert %{
             id: ^audio_track_id,
             type: :audio,
             origin: @endpoint_id,
             encoding: :opus,
             variants: [:high]
           } = engine_audio_track

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)

    transceivers = PeerConnection.get_transceivers(pc)
    assert length(transceivers) == 2
    assert Enum.all?(transceivers, &(&1.current_direction == :sendonly))
  end

  test "peer removes track", %{pc: pc} do
    pipeline = start_pipeline()
    {engine_track, track} = add_peer_video_track(pc, pipeline)

    transceiver =
      pc |> PeerConnection.get_transceivers() |> Enum.find(&(&1.sender.track.id == track.id))

    PeerConnection.remove_track(pc, transceiver.sender.id)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    Pipeline.notify_child(pipeline, :handler, {:offer, sdp_offer(offer), %{}})

    assert_pipeline_notified(
      pipeline,
      :handler,
      {:answer, %{type: :answer, sdp: _sdp} = answer, _new_mid_to_track_id}
    )

    PeerConnection.set_remote_description(pc, answer)

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)

    assert_pipeline_notified(pipeline, :handler, {:tracks_removed, removed_tracks})
    assert removed_tracks |> List.first() == engine_track.id
  end

  test "peer adds incombatible video track" do
    {:ok, pc} = PeerConnection.start_link(video_codecs: [@vp8_codec])

    pipeline = Pipeline.start_link_supervised!(spec: get_pc_handler(video_codec: :H264))

    track_id = UUID.uuid4()
    mid_to_track_id = %{"0" => track_id}
    track_id_to_metadata = %{track_id => @track_metadata}
    track = MediaStreamTrack.new(:video, [MediaStreamTrack.generate_stream_id()])
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, track, direction: :sendonly)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    media_event = sdp_offer(offer, mid_to_track_id, track_id_to_metadata)

    outbound_tracks = %{}
    Pipeline.notify_child(pipeline, :handler, {:offer, media_event, outbound_tracks})

    assert_pipeline_notified(
      pipeline,
      :handler,
      {:answer, %{type: :answer, sdp: _sdp} = answer, _new_mid_to_track_id}
    )

    PeerConnection.set_remote_description(pc, answer)

    # In this case PeerConnection won't return `:connected` state
    # This is because there is no active transciever so there is no reason to connect with other peer
    connect_peer_connection(pipeline, pc, false)

    refute_pipeline_notified(pipeline, :handler, {:new_tracks, _tracks})

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)

    assert [] = PeerConnection.get_transceivers(pc)
  end

  test "peer adds video track to handler with no video codecs", %{pc: pc} do
    pipeline = start_pipeline(video_codec: nil)
    track_id = UUID.uuid4()
    mid_to_track_id = %{"0" => track_id}
    track_id_to_metadata = %{track_id => @track_metadata}
    track = MediaStreamTrack.new(:video, [MediaStreamTrack.generate_stream_id()])
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, track, direction: :sendonly)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    media_event = sdp_offer(offer, mid_to_track_id, track_id_to_metadata)

    outbound_tracks = %{}
    Pipeline.notify_child(pipeline, :handler, {:offer, media_event, outbound_tracks})

    assert_pipeline_notified(
      pipeline,
      :handler,
      {:answer, %{type: :answer, sdp: _sdp} = answer, _new_mid_to_track_id}
    )

    PeerConnection.set_remote_description(pc, answer)

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)

    assert PeerConnection.get_transceivers(pc) == []
  end

  test "raise when transceiver cannot be found", %{pc: pc} do
    pipeline = start_pipeline_unsupervised()
    track_id = UUID.uuid4()
    mid_to_track_id = %{"0" => track_id}
    track_id_to_metadata = %{track_id => @track_metadata}
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, :audio, direction: :sendonly)

    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    media_event = sdp_offer(offer, mid_to_track_id, track_id_to_metadata)

    track = engine_video_track()
    outbound_tracks = %{track.id => track}

    handler = Pipeline.get_child_pid!(pipeline, :handler)
    Process.monitor(handler)

    assert capture_log(fn ->
             Pipeline.notify_child(pipeline, :handler, {:offer, media_event, outbound_tracks})
             Process.sleep(500)
           end) =~ "Failed to find transceiver for track"

    assert_receive {:DOWN, _ref, :process, ^handler, _reason}
  end

  defp start_pipeline(options \\ [video_codec: :VP8]) do
    Pipeline.start_link_supervised!(spec: get_pc_handler(options))
  end

  defp start_pipeline_unsupervised(options \\ [video_codec: :VP8]) do
    {:ok, _supervisor, pipeline} = Pipeline.start(spec: get_pc_handler(options))
    pipeline
  end

  defp get_pc_handler(options) do
    [
      child(:handler, %PeerConnectionHandler{
        endpoint_id: @endpoint_id,
        video_codec: Keyword.get(options, :video_codec)
      })
    ]
  end

  defp sdp_offer(offer, mid_to_track_id \\ %{}, track_id_to_metadata \\ %{}) do
    %{
      sdp_offer: offer,
      mid_to_track_id: mid_to_track_id,
      track_id_to_track_metadata: track_id_to_metadata
    }
  end

  defp engine_video_track() do
    codec =
      PeerConnection.Configuration.default_video_codecs()
      |> Enum.find(&(&1.mime_type == "video/H264"))

    Track.new(
      :video,
      Track.stream_id(),
      @endpoint_id,
      :H264,
      codec.clock_rate,
      codec.sdp_fmtp_line,
      id: UUID.uuid4()
    )
  end

  defp add_peer_video_track(pc, pipeline) do
    track_id = UUID.uuid4()
    track = MediaStreamTrack.new(:video, [MediaStreamTrack.generate_stream_id()])
    {:ok, _transceiver} = PeerConnection.add_transceiver(pc, track, direction: :sendonly)
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    mid_to_track_id = %{"0" => track_id}
    media_event = sdp_offer(offer, mid_to_track_id)

    Pipeline.notify_child(pipeline, :handler, {:offer, media_event, %{}})

    assert_pipeline_notified(
      pipeline,
      :handler,
      {:answer, %SessionDescription{type: :answer} = answer, _mids}
    )

    assert_pipeline_notified(pipeline, :handler, {:new_tracks, tracks})
    [engine_track] = tracks

    assert engine_track.id == track_id

    PeerConnection.set_remote_description(pc, answer)
    connect_peer_connection(pipeline, pc)

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)

    {engine_track, track}
  end

  defp connect_peer_connection(pipeline, pc, should_connect? \\ true) do
    assert_pipeline_notified(pipeline, :handler, {:candidate, candidate})
    PeerConnection.add_ice_candidate(pc, candidate)

    receive do
      {:ex_webrtc, ^pc, {:ice_candidate, candidate}} ->
        Pipeline.notify_child(pipeline, :handler, {:candidate, candidate})
    after
      5000 -> raise "Unable to connect"
    end

    if should_connect? do
      receive do
        {:ex_webrtc, ^pc, {:connection_state_change, :connected}} -> :ok
      after
        5000 -> raise "Unable to connect"
      end
    end
  end
end
