defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC do
  @moduledoc """
  An Endpoint responsible for communicatiing with WebRTC client.
  """
  use Membrane.Bin

  require Membrane.Logger
  require Membrane.TelemetryMetrics

  alias __MODULE__.PeerConnectionHandler

  alias Membrane.RTC.Engine

  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.{
    MediaEvent,
    MediaEventJson,
    TrackReceiver,
    TrackSender
  }

  alias Membrane.RTC.Engine.Notifications.TrackNotification

  @type video_codec :: :H264 | :VP8 | nil

  @type track_variant :: :low | :medium | :high

  @typedoc """
  "l" | "m" | "h"
  """
  @type rid :: String.t()

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ],
              video_codec: [
                spec: video_codec,
                description: "Allowed video codec",
                default: :H264
              ],
              metadata: [
                spec: any(),
                default: nil,
                description: "Endpoint metadata"
              ],
              telemetry_label: [
                spec: Membrane.TelemetryMetrics.label(),
                default: [],
                description: "Label passed to Membrane.TelemetryMetrics functions"
              ],
              event_serialization: [
                spec: :json | :protobuf,
                description: "Serialization method for encoding and decoding Media Events"
              ],
              ignored_endpoints: [
                spec: [Endpoint.id()],
                default: [],
                description: "List of endpoint IDs to ignore"
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request

  defmodule Track do
    @moduledoc false

    @enforce_keys [:status, :engine_track]
    defstruct @enforce_keys ++ [subscribe_ref: nil]

    @typedoc """
    Describes outbound tracks status
    :pending - the track is awaiting previous negotiation to finish
    :negotiating - track during negotiation
    :subscribing - waiting for subscription from engine
    :subscribed - completed subscription from engine
    """
    @type status :: :pending | :negotiating | :subscribing | :subscribed

    @type t :: %{
            status: status(),
            engine_track: Engine.Track.t(),
            subscribe_ref: reference()
          }
  end

  @impl true
  def handle_init(ctx, opts) do
    {:endpoint, endpoint_id} = ctx.name
    Logger.metadata(endpoint_id: endpoint_id)

    opts = Map.update!(opts, :telemetry_label, &(&1 ++ [endpoint_id: endpoint_id]))

    state =
      opts
      |> Map.from_struct()
      |> Map.merge(%{
        outbound_tracks: %{},
        inbound_tracks: %{},
        track_id_to_bitrates: %{},
        negotiation?: false,
        queued_negotiation?: false,
        removed_tracks: %{audio: 0, video: 0},
        event_serializer: get_event_serializer(opts.event_serialization)
      })
      |> Map.delete(:event_serialization)

    spec = [
      child(:connection_handler, %PeerConnectionHandler{
        endpoint_id: endpoint_id,
        video_codec: opts.video_codec,
        telemetry_label: opts.telemetry_label
      })
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {track_id, variant}) = pad, _ctx, state) do
    track = Map.fetch!(state.inbound_tracks, track_id)

    track_sender = %TrackSender{
      track: track,
      variant_bitrates: Map.get(state.track_id_to_bitrates, track_id, %{})
    }

    spec = [
      get_child(:connection_handler)
      |> via_out(pad)
      |> via_in(Pad.ref(:input, {track_id, variant}))
      |> child({:track_sender, track_id}, track_sender, get_if_exists: true)
      |> via_out(pad)
      |> bin_output(pad)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, track_id) = pad, _ctx, state) do
    track = Map.fetch!(state.outbound_tracks, track_id)

    spec =
      bin_input(pad)
      |> child({:track_receiver, track_id}, %TrackReceiver{
        track: track.engine_track,
        initial_target_variant: :high
      })
      |> via_in(pad)
      |> get_child(:connection_handler)

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, track_id), _ctx, state) do
    {[remove_children: {:track_receiver, track_id}], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:output, {_track_id, _variant}), _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification(
        {:ready, endpoints},
        ctx,
        %{event_serializer: serializer} = state
      ) do
    case Enum.reject(endpoints, &(&1.id in state.ignored_endpoints)) do
      [] ->
        {[], state}

      endpoints ->
        {:endpoint, endpoint_id} = ctx.name

        log_endpoints =
          Enum.map(endpoints, fn endpoint ->
            endpoint |> Map.from_struct() |> Map.delete(:inbound_tracks)
          end)

        Membrane.Logger.info("endpoint ready, endpoints: #{inspect(log_endpoints)}")

        action =
          endpoint_id
          |> serializer.connected(
            endpoints,
            Application.get_env(:membrane_rtc_engine_ex_webrtc, :ice_servers, [])
          )
          |> serializer.to_action()

        {action, state}
    end
  end

  @impl true
  def handle_parent_notification(
        {:new_endpoint, endpoint},
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    if endpoint.id in state.ignored_endpoints do
      {[], state}
    else
      action = endpoint |> serializer.endpoint_added() |> serializer.to_action()
      Membrane.Logger.debug("endpoint added: #{inspect(endpoint)}")
      {action, state}
    end
  end

  @impl true
  def handle_parent_notification(
        {:endpoint_removed, endpoint_id},
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    if endpoint_id in state.ignored_endpoints do
      {[], state}
    else
      action = endpoint_id |> serializer.endpoint_removed() |> serializer.to_action()
      {action, state}
    end
  end

  @impl true
  def handle_parent_notification(
        {:track_metadata_updated, %Engine.Track{origin: endpoint_id} = track},
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    if endpoint_id in state.ignored_endpoints do
      {[], state}
    else
      event =
        endpoint_id
        |> serializer.track_updated(track.id, track.metadata)
        |> serializer.to_action()

      {event, state}
    end
  end

  @impl true
  def handle_parent_notification({:track_variant_enabled, _track, _variant}, _ctx, state) do
    # TODO: add simulcast support
    {[], state}
  end

  @impl true
  def handle_parent_notification({:track_variant_disabled, _track, _variant}, _ctx, state) do
    # TODO: add simulcast support
    {[], state}
  end

  @impl true
  def handle_parent_notification(
        {:endpoint_metadata_updated, endpoint},
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    if endpoint.id in state.ignored_endpoints do
      {[], state}
    else
      event = endpoint |> serializer.endpoint_updated() |> serializer.to_action()
      {event, state}
    end
  end

  @impl true
  def handle_parent_notification({:new_tracks, new_tracks}, _ctx, %{negotiation?: true} = state) do
    Membrane.Logger.debug("new parent queued tracks: #{log_tracks(new_tracks)}")

    new_tracks =
      new_tracks
      |> Enum.reject(&(&1.origin in state.ignored_endpoints))
      |> Map.new(&{&1.id, %Track{status: :pending, engine_track: &1}})

    outbound_tracks = Map.merge(state.outbound_tracks, new_tracks)

    tracks_added = get_new_tracks_actions(new_tracks, state)
    {tracks_added, %{state | outbound_tracks: outbound_tracks}}
  end

  @impl true
  def handle_parent_notification({:new_tracks, new_tracks}, _ctx, state) do
    Membrane.Logger.debug("new parent tracks: #{log_tracks(new_tracks)}")

    new_tracks =
      new_tracks
      |> Enum.reject(&(&1.origin in state.ignored_endpoints))
      |> Map.new(&{&1.id, %Track{status: :pending, engine_track: &1}})

    new_tracks =
      state.outbound_tracks
      |> Map.filter(fn {_id, track} -> track.status == :pending end)
      |> Map.merge(new_tracks)
      |> Map.new(fn {id, track} -> {id, %{track | status: :negotiating}} end)

    state = update_in(state.outbound_tracks, &Map.merge(&1, new_tracks))

    tracks_added = get_new_tracks_actions(new_tracks, state)

    case tracks_added do
      [] ->
        {[], state}

      tracks_added ->
        offer_data = get_offer_data(state)
        {tracks_added ++ offer_data, %{state | negotiation?: true}}
    end
  end

  @impl true
  def handle_parent_notification({:remove_tracks, tracks}, _ctx, state) do
    tracks = Enum.reject(tracks, &(&1.origin in state.ignored_endpoints))
    track_ids = Enum.map(tracks, & &1.id)

    state = update_in(state.outbound_tracks, &Map.drop(&1, track_ids))

    audio_removed_tracks = state.removed_tracks.audio + Enum.count(tracks, &(&1.type == :audio))
    video_removed_tracks = state.removed_tracks.video + Enum.count(tracks, &(&1.type == :video))

    state = %{state | removed_tracks: %{audio: audio_removed_tracks, video: video_removed_tracks}}

    Membrane.Logger.debug("remove tracks event for #{inspect(tracks)}")

    actions = build_track_removed_actions(tracks, state)

    {actions, state}
  end

  @impl true
  def handle_parent_notification({:media_event, event}, ctx, state) do
    case deserialize(event, state) do
      {:ok, type, data} ->
        handle_media_event(type, data, ctx, state)

      {:error, :invalid_media_event} ->
        Membrane.Logger.error("Invalid media event #{inspect(event)}. Ignoring.")
        {[], state}
    end
  end

  @impl true
  def handle_parent_notification(%TrackNotification{}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification(_msg, _ctx, state) do
    {[], state}
  end

  defp log_tracks(tracks) do
    tracks
    |> Enum.map(
      &Map.take(&1, [:type, :stream_id, :id, :origin, :encoding, :variants, :disabled_variants])
    )
    |> inspect()
  end

  defp handle_media_event(:connect, %{metadata: metadata}, _ctx, state) do
    actions =
      if is_map(metadata) and Map.has_key?(metadata, "displayName") do
        Logger.metadata(peer: metadata["displayName"])
        [notify_child: {:connection_handler, {:set_metadata, metadata["displayName"]}}]
      else
        []
      end

    {actions ++ [notify_parent: {:ready, metadata}], state}
  end

  defp handle_media_event(:disconnect, _data, _ctx, state) do
    {[notify_parent: :finished], state}
  end

  defp handle_media_event(
         :disable_track_variant,
         %{track_id: track_id, variant: variant},
         _ctx,
         state
       ) do
    {[notify_parent: {:disable_track_variant, track_id, variant}], state}
  end

  defp handle_media_event(
         :enable_track_variant,
         %{track_id: track_id, variant: variant},
         _ctx,
         state
       ) do
    {[notify_parent: {:enable_track_variant, track_id, variant}], state}
  end

  defp handle_media_event(
         :set_target_track_variant,
         %{track_id: track_id, variant: variant},
         ctx,
         state
       )
       when is_map_key(ctx.children, {:track_receiver, track_id}) do
    msg = {:set_target_variant, variant}
    {[notify_child: {{:track_receiver, track_id}, msg}], state}
  end

  defp handle_media_event(:set_target_track_variant, %{track_id: track_id}, _ctx, state) do
    Membrane.Logger.warning(
      "Received set target variant media event for unknown track: #{track_id}"
    )

    {[], state}
  end

  defp handle_media_event(:update_endpoint_metadata, %{metadata: metadata}, _ctx, state) do
    {[notify_parent: {:update_endpoint_metadata, metadata}], state}
  end

  defp handle_media_event(
         :update_track_metadata,
         %{track_id: track_id, track_metadata: metadata},
         _ctx,
         state
       ) do
    {[notify_parent: {:update_track_metadata, track_id, metadata}], state}
  end

  defp handle_media_event(:sdp_offer, event, _ctx, state) do
    new_tracks =
      state.outbound_tracks
      |> Map.filter(fn {_id, t} -> t.status == :negotiating end)
      |> Map.new(fn {id, t} -> {id, t.engine_track} end)

    state = put_in(state.track_id_to_bitrates, event.track_id_to_track_bitrates)
    {[notify_child: {:connection_handler, {:offer, event, new_tracks}}], state}
  end

  defp handle_media_event(:candidate, candidate, _ctx, state) do
    {[notify_child: {:connection_handler, {:candidate, candidate}}], state}
  end

  defp handle_media_event(:renegotiate_tracks, _data, _ctx, %{negotiation?: true} = state) do
    {[], %{state | queued_negotiation?: true}}
  end

  defp handle_media_event(:renegotiate_tracks, _data, _ctx, state) do
    actions = get_offer_data(state)

    {actions, %{state | negotiation?: true}}
  end

  defp handle_media_event(:track_bitrates, data, _ctx, state) do
    state = put_in(state, [:track_id_to_bitrates, data.track_id], data.bitrates)
    msg = {:variant_bitrates, data.bitrates}

    {[notify_child: {{:track_sender, data.track_id}, msg}], state}
  end

  defp handle_media_event(:unmute_track, %{track_id: track_id}, ctx, state)
       when is_map_key(ctx.children, {:track_sender, track_id}) do
    {[notify_child: {{:track_sender, track_id}, :unmute_track}], state}
  end

  defp handle_media_event(:unmute_track, %{track_id: track_id}, _ctx, state) do
    Membrane.Logger.warning("Received unmute track media event for unknown track: #{track_id}")
    {[], state}
  end

  defp handle_media_event(type, event, _ctx, state) do
    Membrane.Logger.warning("unexpected media event: #{type}, #{inspect(event)}")
    {[], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, tracks}, :connection_handler, _ctx, state) do
    Membrane.Logger.debug("new webrtc tracks: #{log_tracks(tracks)}")

    new_inbound_tracks = Map.new(tracks, fn track -> {track.id, track} end)
    state = update_in(state.inbound_tracks, &Map.merge(&1, new_inbound_tracks))

    new_tracks = [notify_parent: {:publish, {:new_tracks, tracks}}]
    {new_tracks, state}
  end

  @impl true
  def handle_child_notification(
        {:track_ready, id, _variant, _encoding} = msg,
        :connection_handler,
        _ctx,
        state
      ) do
    Membrane.Logger.debug("Track ready, id: #{id}")
    {[notify_parent: msg], state}
  end

  @impl true
  def handle_child_notification({:tracks_removed, track_ids}, :connection_handler, ctx, state) do
    Membrane.Logger.debug("webrtc tracks removed")

    tracks = state.inbound_tracks |> Map.take(track_ids) |> Map.values()
    inbound_tracks = Map.drop(state.inbound_tracks, track_ids)

    track_senders =
      track_ids
      |> Enum.map(&{:track_sender, &1})
      |> Enum.filter(&Map.has_key?(ctx.children, &1))

    actions = [
      remove_children: track_senders,
      notify_parent: {:publish, {:removed_tracks, tracks}}
    ]

    {actions, %{state | inbound_tracks: inbound_tracks}}
  end

  @impl true
  def handle_child_notification(
        {:answer, answer, mid_to_track_id},
        :connection_handler,
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    actions = answer |> serializer.sdp_answer(mid_to_track_id) |> serializer.to_action()

    {actions, state}
  end

  @impl true
  def handle_child_notification(
        {:candidate, candidate},
        :connection_handler,
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    actions = candidate |> serializer.candidate() |> serializer.to_action()
    {actions, state}
  end

  @impl true
  def handle_child_notification(
        :negotiation_done,
        :connection_handler,
        %{name: {:endpoint, endpoint_id}},
        %{negotiation?: true} = state
      ) do
    negotiated_tracks =
      state.outbound_tracks
      |> Map.filter(fn {_id, t} -> t.status == :negotiating end)
      |> Map.new(fn {id, track} ->
        ref = Engine.subscribe_async(state.rtc_engine, endpoint_id, id)
        {id, %{track | status: :subscribing, subscribe_ref: ref}}
      end)

    state = update_in(state.outbound_tracks, &Map.merge(&1, negotiated_tracks))
    pending_tracks = Map.filter(state.outbound_tracks, fn {_id, t} -> t.status == :pending end)

    if Enum.empty?(pending_tracks) and not state.queued_negotiation? do
      {[], %{state | negotiation?: false}}
    else
      new_tracks =
        Map.new(pending_tracks, fn {id, track} -> {id, %{track | status: :negotiating}} end)

      state = update_in(state.outbound_tracks, &Map.merge(&1, new_tracks))

      offer_data = get_offer_data(state)
      {offer_data, %{state | negotiation?: true, queued_negotiation?: false}}
    end
  end

  @impl true
  def handle_child_notification(
        :renegotiate,
        :connection_handler,
        _ctx,
        %{negotiation?: true} = state
      ) do
    {[], %{state | queued_negotiation?: true}}
  end

  @impl true
  def handle_child_notification(:renegotiate, :connection_handler, _ctx, state) do
    actions = get_offer_data(state)

    {actions, %{state | negotiation?: true}}
  end

  @impl true
  def handle_child_notification(
        {:estimation, estimations},
        {:track_sender, track_id},
        _ctx,
        state
      ) do
    notification = %TrackNotification{
      track_id: track_id,
      notification: bitrate_notification(estimations)
    }

    {[notify_parent: {:publish, notification}], state}
  end

  @impl true
  def handle_child_notification(
        {:voice_activity_changed, vad},
        {:track_receiver, track_id},
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    action = track_id |> serializer.voice_activity(vad) |> serializer.to_action()
    {action, state}
  end

  @impl true
  def handle_child_notification(_msg, _child, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info(
        {:subscribe_result, subscribe_ref, {:ok, engine_track}},
        _ctx,
        %{event_serializer: serializer} = state
      ) do
    {track_id, track} =
      Enum.find(state.outbound_tracks, fn {_id, t} -> t.subscribe_ref == subscribe_ref end)

    track = %{track | status: :subscribed, subscribe_ref: nil}

    {actions, track} =
      if engine_track.metadata == track.engine_track.metadata do
        {[], track}
      else
        event =
          serializer.track_updated(track.engine_track.origin, track_id, engine_track.metadata)
          |> serializer.to_action()

        track = put_in(track.engine_track.metadata, engine_track.metadata)
        {event, track}
      end

    state = update_in(state.outbound_tracks, &Map.put(&1, track_id, track))
    {actions, state}
  end

  @impl true
  def handle_info({:subscribe_result, subscribe_ref, :ignored}, _ctx, state) do
    {track_id, track} =
      Enum.find(state.outbound_tracks, fn {_id, t} -> t.subscribe_ref == subscribe_ref end)

    Membrane.Logger.warning("Subscription for track #{track_id} failed")

    state =
      update_in(state, [:removed_tracks, track.engine_track.type], fn count -> count + 1 end)

    state = update_in(state.outbound_tracks, &Map.delete(&1, track_id))
    actions = build_track_removed_actions([track.engine_track], state)

    {actions, state}
  end

  @spec to_rid(track_variant()) :: rid()
  def to_rid(:high), do: "h"
  def to_rid(:medium), do: "m"
  def to_rid(:low), do: "l"

  @spec to_track_variant(rid() | nil) :: track_variant()
  def to_track_variant(rid) when rid in ["h", nil], do: :high
  def to_track_variant("m"), do: :medium
  def to_track_variant("l"), do: :low

  defp get_media_count(state) do
    tracks_types =
      state.outbound_tracks
      |> Map.values()
      |> Enum.map(& &1.engine_track.type)

    %{
      audio: Enum.count(tracks_types, &(&1 == :audio)) + state.removed_tracks.audio,
      video: Enum.count(tracks_types, &(&1 == :video)) + state.removed_tracks.video
    }
  end

  defp get_offer_data(%{event_serializer: serializer} = state) do
    state
    |> get_media_count()
    |> serializer.offer_data()
    |> serializer.to_action()
  end

  defp get_new_tracks_actions(new_tracks, %{event_serializer: serializer}) do
    new_tracks
    |> Map.values()
    |> Enum.map(& &1.engine_track)
    |> Enum.group_by(& &1.origin)
    |> Enum.flat_map(fn {origin, tracks} ->
      serializer.tracks_added(origin, tracks)
      |> serializer.to_action()
    end)
  end

  defp bitrate_notification(estimation) do
    {:bitrate_estimation, estimation}
  end

  defp deserialize(event, state) when is_binary(event) do
    case state.event_serializer.decode(event) do
      {:ok, %{type: :custom, data: %{type: type} = event}} -> {:ok, type, Map.get(event, :data)}
      {:ok, %{type: type} = event} -> {:ok, type, Map.get(event, :data)}
      {:error, _reason} = error -> error
    end
  end

  defp build_track_removed_actions([], _state), do: []

  defp build_track_removed_actions(tracks, %{event_serializer: serializer}) do
    tracks_removed_events =
      tracks
      |> Enum.group_by(& &1.origin)
      |> Enum.flat_map(fn {endpoint_id, tracks} ->
        track_ids = Enum.map(tracks, & &1.id)
        endpoint_id |> serializer.tracks_removed(track_ids) |> serializer.to_action()
      end)

    track_ids = Enum.map(tracks, & &1.id)
    notify_handler = [notify_child: {:connection_handler, {:tracks_removed, track_ids}}]

    tracks_removed_events ++ notify_handler
  end

  defp get_event_serializer(:protobuf), do: MediaEvent
  defp get_event_serializer(:json), do: MediaEventJson
end
