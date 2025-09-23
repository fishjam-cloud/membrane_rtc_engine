defmodule Membrane.RTC.Engine.Endpoint.Agent do
  @moduledoc """
  An Endpoint responsible for allowing programmatic publishing and receiving tracks in a room.

  Currently, the Agent Endpoint supports:
  * receiving audio tracks from room in raw 16-bit PCM with 1 channel and 16kHz or 24kHz sample rate
  * publishing 1 channel audio tracks to room, in OPUS, or raw 16-bit PCM 16kHz or 24kHz sample rate
  """

  use Membrane.Bin

  require Membrane.Logger

  alias Membrane.RawAudioParser
  alias Membrane.RTP.PayloaderBin

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.{Endpoint, Subscriber, Track}
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.TrackReceiver
  alias Membrane.RTC.Engine.StaticTrackSender

  alias Fishjam.{AgentRequest, AgentResponse}
  alias Fishjam.AgentRequest.{AddTrack, InterruptTrack, RemoveTrack, TrackData}

  alias __MODULE__.{AudioBuffer, Timestamper, TrackDataPublisher, TrackDataForwarder, TrackUtils}

  @type encoding_t() :: String.t()

  @type output_format() :: :pcm16
  @type output_sample_rate() :: 16_000 | 24_000

  @type codec_parameters() :: %{
          channels: 1,
          encoding: :opus | :pcm16,
          sample_rate: non_neg_integer()
        }

  @type state() :: %{
          subscriber: Subscriber.t(),
          outputs: %{
            Endpoint.id() => %{
              format: output_format(),
              sample_rate: output_sample_rate()
            }
          },
          inputs: %{
            Track.id() => %{
              track: Track.t(),
              codec_parameters: codec_parameters()
            }
          }
        }

  @opus_sample_rate 48_000

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request

  @doc """
  Subscribe agent endpoint to tracks from given endpoint.
  """
  @spec subscribe(
          engine :: pid(),
          agent_id :: String.t(),
          endpoint_id :: String.t(),
          opts :: [format: output_format(), sample_rate: output_sample_rate()]
        ) :: :ok
  def subscribe(engine, agent_id, endpoint_id, opts) do
    Engine.message_endpoint(engine, agent_id, {:subscribe, endpoint_id, opts})
  end

  @impl true
  def handle_init(ctx, opts) do
    {:endpoint, endpoint_id} = ctx.name

    subscriber = %Subscriber{
      endpoint_id: endpoint_id,
      subscribe_mode: :manual,
      rtc_engine: opts.rtc_engine,
      track_types: [:audio]
    }

    state = %{
      subscriber: subscriber,
      inputs: %{},
      outputs: %{}
    }

    spec = [
      child(:track_data_publisher, TrackDataPublisher),
      child(:track_data_forwarder, TrackDataForwarder)
    ]

    {[notify_parent: :ready, spec: spec], state}
  end

  @impl true
  def handle_pad_added(
        Pad.ref(:input, track_id) = pad,
        _ctx,
        %{subscriber: subscriber, outputs: outputs} = state
      ) do
    with %Track{type: :audio, encoding: encoding} = track <-
           Subscriber.get_track(subscriber, track_id),
         {:ok, output} <- Map.fetch(outputs, track.origin),
         depayloader when depayloader != nil <- Track.get_depayloader(track),
         decoder when decoder != nil <- get_decoder(encoding) do
      spec =
        {bin_input(pad)
         |> child({:track_receiver, track_id}, %TrackReceiver{
           track: track,
           initial_target_variant: :high
         })
         |> child({:depayloader, track_id}, depayloader)
         |> child({:opus_decoder, track_id}, decoder)
         |> child({:mixer, track_id}, %Membrane.FFmpeg.SWResample.Converter{
           input_stream_format: nil,
           output_stream_format: %Membrane.RawAudio{
             channels: 1,
             sample_format: :s16le,
             sample_rate: output.sample_rate
           }
         })
         |> via_in(pad)
         |> get_child(:track_data_publisher), group: {:transcoding_group, track_id}}

      Membrane.Logger.info("Subscribed to track #{inspect(track_id)}")
      {[spec: spec], state}
    else
      unsupported ->
        Membrane.Logger.warning(
          "Ignoring track #{inspect(track_id)}, reason: #{inspect(unsupported)}"
        )

        {[], state}
    end
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {track_id, :high}) = pad, _ctx, state) do
    %{track: track, codec_parameters: codec_params} = Map.fetch!(state.inputs, track_id)

    payloader_bin = get_payloader(track)

    spec =
      {get_child(:track_data_forwarder)
       |> via_out(Pad.ref(:output, track_id))
       |> get_parser(codec_params.encoding)
       |> child(:timestamper, Timestamper)
       |> child(:audio_buffer, %AudioBuffer{max_buffered_duration: Membrane.Time.minutes(10)})
       # Queue size 1 to minimize interruption delay, which is target_queue_size * 60ms
       |> via_in(:input, target_queue_size: 1)
       |> child(:realtimer, Membrane.Realtimer)
       |> get_encoder(codec_params.encoding)
       |> child(:payloader, payloader_bin)
       |> child(:track_sender, %StaticTrackSender{
         track: track,
         is_keyframe: fn _buf, _end -> true end
       })
       |> bin_output(pad), group: {:forwarding_group, track_id}}

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, track_id), _ctx, state) do
    {[remove_children: {:transcoding_group, track_id}], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:output, {track_id, :high}), _ctx, state) do
    {[remove_children: {:forwarding_group, track_id}], state}
  end

  @impl true
  def handle_child_notification(
        {:track_data, track_id, data},
        :track_data_publisher,
        _ctx,
        %{subscriber: subscriber} = state
      ) do
    case Subscriber.get_track(subscriber, track_id) do
      nil ->
        raise(
          "Received track data notification from endpoint for unknown track #{inspect(track_id)}"
        )

      track ->
        track_data = get_track_data_msg(data, track)

        {[
           notify_parent: {:forward_to_parent, track_data}
         ], state}
    end
  end

  @impl true
  def handle_child_notification(
        {:track_finished, track_id},
        :track_data_publisher,
        _ctx,
        %{subscriber: subscriber} = state
      ) do
    subscriber = Subscriber.remove_track(subscriber, track_id)
    {[], %{state | subscriber: subscriber}}
  end

  @impl true
  def handle_child_notification(
        {:variant_switched, _variant, _reason},
        {:track_receiver, _track_id},
        _ctx,
        state
      ) do
    {[], state}
  end

  @impl true
  def handle_child_notification(
        {:voice_activity_changed, _new_state},
        {:track_receiver, _track_id},
        _ctx,
        state
      ) do
    {[], state}
  end

  @impl true
  def handle_child_notification(msg, child, _ctx, state) do
    Membrane.Logger.warning("Unexpected notification #{inspect(msg)} from #{inspect(child)}")
    {[], state}
  end

  @impl true
  def handle_parent_notification({:new_tracks, tracks}, _ctx, state) do
    subscriber = Subscriber.handle_new_tracks(tracks, state.subscriber)

    {[], %{state | subscriber: subscriber}}
  end

  @impl true
  def handle_parent_notification(
        {:endpoint_removed, endpoint_id},
        _ctx,
        %{subscriber: subscriber, outputs: outputs} = state
      ) do
    subscriber = Subscriber.remove_endpoints(subscriber, [endpoint_id])
    outputs = Map.delete(outputs, endpoint_id)

    Membrane.Logger.info("Removed subscription for endpoint #{inspect(endpoint_id)}")

    {[], %{state | subscriber: subscriber, outputs: outputs}}
  end

  @impl true
  def handle_parent_notification(
        {:subscribe, endpoint_id, [format: format, sample_rate: sample_rate]},
        _ctx,
        %{subscriber: subscriber, outputs: outputs} = state
      ) do
    subscriber = Subscriber.add_endpoints([endpoint_id], subscriber)
    outputs = Map.put(outputs, endpoint_id, %{format: format, sample_rate: sample_rate})

    Membrane.Logger.info("Subscribed to endpoint #{inspect(endpoint_id)}")

    {[], %{state | subscriber: subscriber, outputs: outputs}}
  end

  @impl true
  def handle_parent_notification({:agent_notification, request}, ctx, state) do
    %AgentRequest{content: {_name, content}} = request
    handle_agent_request(content, ctx, state)
  end

  @impl true
  def handle_parent_notification(_msg, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_element_end_of_stream(:track_sender, Pad.ref(:input), _ctx, state) do
    track = state.inputs |> Map.values() |> List.first() |> Map.fetch!(:track)

    actions = [notify_parent: {:publish, {:removed_tracks, [track]}}]

    {actions, state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  defp handle_agent_request(%AddTrack{} = request, ctx, state) do
    %{track: track, codec_params: codec_params} = request
    {:endpoint, endpoint_id} = ctx.name

    with :ok <- validate_track_id(track.id, state),
         {:ok, new_track, parsed_codec_params} <- TrackUtils.create_track(request, endpoint_id) do
      track_info = %{track: new_track, codec_parameters: parsed_codec_params}

      state = put_in(state, [:inputs, track.id], track_info)

      actions = [
        notify_child: {:track_data_forwarder, {:new_track, track.id, parsed_codec_params}},
        notify_parent: {:publish, {:new_tracks, [new_track]}},
        notify_parent: {:track_ready, new_track.id, :high, :opus}
      ]

      {actions, state}
    else
      {:error, :invalid_track_id} ->
        raise("AddTrack request with invalid track_id #{inspect(track.id)}")

      {:error, :invalid_track_type} ->
        raise("AddTrack request with invalid track type - only audio tracks are supported")

      {:error, :invalid_codec_params} ->
        raise("AddTrack request with invalid codec params #{inspect(codec_params)}")
    end
  end

  # TODO: Send notification to per-track audio buffer
  defp handle_agent_request(%InterruptTrack{track_id: _track_id}, _ctx, state) do
    {[notify_child: {:timestamper, :interrupt}], state}
  end

  defp handle_agent_request(%RemoveTrack{track_id: track_id}, _ctx, state) do
    with %{track: _track} <- get_in(state, [:inputs, track_id]) do
      {[notify_child: {:track_data_forwarder, {:remove_track, track_id}}], state}
    else
      {nil, state} ->
        Membrane.Logger.error("Requested removing non-existent track #{inspect(track_id)}")
        {[], state}
    end
  end

  defp handle_agent_request(
         %TrackData{track_id: track_id, data: data},
         _ctx,
         %{inputs: inputs} = state
       ) do
    with true <- Map.has_key?(inputs, track_id) do
      notification = {:track_data, track_id, data}

      {[notify_child: {:track_data_forwarder, notification}], state}
    else
      false ->
        raise("Received track data from remote for unknown track #{inspect(track_id)}")
    end
  end

  defp get_decoder(:opus), do: Membrane.Opus.Decoder
  defp get_decoder(_other), do: nil

  defp get_payloader(track) do
    %PayloaderBin{
      payloader: Membrane.RTP.Opus.Payloader,
      ssrc: generate_ssrc(),
      payload_type: track.payload_type,
      clock_rate: @opus_sample_rate
    }
  end

  defp get_parser(pipeline, :pcm16), do: child(pipeline, :parser, RawAudioParser)
  defp get_parser(pipeline, :opus), do: child(pipeline, :parser, Membrane.Opus.Parser)

  defp get_encoder(pipeline, :pcm16), do: child(pipeline, :encoder, Membrane.Opus.Encoder)
  defp get_encoder(pipeline, :opus), do: pipeline

  defp get_track_data_msg(data, track) do
    {:track_data,
     %AgentResponse.TrackData{
       peer_id: track.origin,
       track: TrackUtils.to_proto_track(track),
       data: data
     }}
  end

  defp validate_track_id(track_id, %{subscriber: subscriber, inputs: inputs}) do
    with {:ok, uuid} <- UUID.info(track_id),
         4 <- Keyword.get(uuid, :version),
         nil <- Subscriber.get_track(subscriber, track_id),
         false <- Map.has_key?(inputs, track_id) do
      :ok
    else
      _error ->
        {:error, :invalid_track_id}
    end
  end

  defp generate_ssrc() do
    :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned()
  end
end
