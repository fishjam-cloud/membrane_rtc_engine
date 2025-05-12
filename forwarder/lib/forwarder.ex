defmodule Membrane.RTC.Engine.Endpoint.Forwarder do
  @moduledoc """
  An Endpoint responsible for forwarding single stream to an external broadcaster using WHIP standard.
  """
  use Membrane.Bin

  require Membrane.Logger
  require Membrane.TelemetryMetrics

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.TrackReceiver
  alias Membrane.RTC.Engine.Endpoint.Forwarder.PeerConnectionHandler

  def_options rtc_engine: [
                spec: pid(),
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
              ],
              whip_endpoint: [
                spec: String.t(),
                description: "WHIP endpoint path"
              ],
              video_codec: [
                spec: :h264 | :vp8,
                description: "Video codec of forwarded video track"
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request

  @impl true
  def handle_init(ctx, opts) do
    {:endpoint, endpoint_id} = ctx.name

    state =
      opts
      |> Map.update!(:telemetry_label, &(&1 ++ [endpoint_id: endpoint_id]))
      |> Map.merge(%{
        forwarded_tracks: %{video: nil, audio: nil},
        tracks: [],
        forwarding?: false,
        endpoint_id: endpoint_id
      })

    Logger.metadata(state.telemetry_label)

    spec = spawn_peer_connection_handler(state)

    {[spec: spec, notify_parent: {:ready, nil}], state}
  end

  defp spawn_peer_connection_handler(state) do
    [
      child(:connection_handler, %PeerConnectionHandler{
        endpoint_id: state.endpoint_id,
        whip_endpoint: state.whip_endpoint,
        telemetry_label: state.telemetry_label,
        broadcaster_url: state.broadcaster_url,
        broadcaster_token: state.broadcaster_token,
        video_codec: state.video_codec
      })
    ]
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, track_id) = pad, _ctx, state) do
    {_type, track} =
      Enum.find(state.forwarded_tracks, fn {_type, track} -> track.id == track_id end)

    track_receiver = %TrackReceiver{track: track, initial_target_variant: :h}

    spec =
      bin_input(pad)
      |> child({:track_receiver, track_id}, track_receiver)
      |> via_in(pad)
      |> get_child(:connection_handler)

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, track_id), _ctx, state) do
    {[remove_children: {:track_receiver, track_id}], state}
  end

  @impl true
  def handle_parent_notification({:new_tracks, _new_tracks}, _ctx, %{forwarding?: true} = state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification({:new_tracks, new_tracks}, _ctx, state) do
    tracks = state.tracks ++ new_tracks

    video_track = Enum.find(tracks, &(&1.type == :video))
    audio_track = Enum.find(tracks, &(&1.type == :audio))

    if audio_track && video_track do
      Membrane.Logger.info("Got audio and video track. Starting negotation with broadcaster...")

      state = %{
        state
        | forwarded_tracks: %{
            video: video_track,
            audio: audio_track
          }
      }

      {[notify_child: {:connection_handler, {:start_negotiation, state.forwarded_tracks}}],
       %{state | tracks: tracks, forwarding?: true}}
    else
      {[], %{state | tracks: tracks}}
    end
  end

  @impl true
  def handle_parent_notification({:remove_tracks, tracks}, _ctx, %{forwarding?: true} = state) do
    tracks_used? =
      tracks
      |> Enum.map(& &1.id)
      |> Enum.any?(&(&1 in [state.forwarded_tracks.video.id, state.forwarded_tracks.audio.id]))

    if tracks_used? do
      Membrane.Logger.info("Terminating because source tracks were removed")
      {[terminate: {:shutdown, :tracks_removed}], state}
    else
      {[], state}
    end
  end

  def handle_parent_notification({:remove_tracks, remove_tracks}, _ctx, state) do
    remove_tracks_ids = Enum.map(remove_tracks, & &1.id)
    tracks = Enum.filter(state.tracks, &(&1.id not in remove_tracks_ids))

    {[], %{state | tracks: tracks}}
  end

  @impl true
  def handle_parent_notification(msg, _ctx, state) do
    Membrane.Logger.debug("Ignoring parent notification: #{inspect(msg)}")
    {[], state}
  end

  @impl true
  def handle_child_notification(:negotiation_done, :connection_handler, _ctx, state) do
    Membrane.Logger.info("Succesfully connected to broadcaster")

    with {:ok, _track} <-
           Engine.subscribe(state.rtc_engine, state.endpoint_id, state.forwarded_tracks.video.id),
         {:ok, _track} <-
           Engine.subscribe(state.rtc_engine, state.endpoint_id, state.forwarded_tracks.audio.id) do
      {[], state}
    else
      # If one of the tracks was removed during negotiation, subscribe will return :ignored
      :ignored -> {[terminate: {:shutdown, :tracks_removed}], state}
    end
  end

  @impl true
  def handle_child_notification(msg, {:track_receiver, _track_id}, _ctx, state) do
    Membrane.Logger.debug("Ignoring child notification: #{inspect(msg)}")
    {[], state}
  end
end
