defmodule Membrane.RTC.Engine.Endpoint.Transcoder do
  @moduledoc """
  An Endpoint responsible for receiving data in one codec, transcoding it and publishing it to the engine parent process.

  Currently, the Transcoder Endpoint only supports decoding to raw 16-bit PCM
  with sample rate either 16kHz or 24kHz and 1 channel.
  """

  use Membrane.Bin

  require Membrane.Logger

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.{Endpoint, Subscriber, Track, TrackReceiver}
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.TrackReceiver
  alias Membrane.RTC.Engine.Endpoint.Transcoder.TrackDataPublisher

  @type encoding_t() :: String.t()

  @type output_format() :: :pcm16
  @type output_sample_rate() :: 16_000 | 24_000

  @type state() :: %{
          subscriber: Subscriber.t(),
          outputs: %{
            Endpoint.id() => %{
              format: output_format(),
              sample_rate: output_sample_rate()
            }
          }
        }

  def_options(
    rtc_engine: [
      spec: pid(),
      description: "Pid of parent Engine"
    ]
  )

  def_input_pad(:input,
    accepted_format: _any,
    availability: :on_request
  )

  @doc """
  Subscribe transcoder endpoint to tracks from given endpoint.
  """
  @spec subscribe(
          engine :: pid(),
          transcoder_id :: any(),
          endpoint_id :: any(),
          opts :: [format: output_format(), sample_rate: output_sample_rate()]
        ) :: :ok
  def subscribe(engine, transcoder_id, endpoint_id, opts) do
    Engine.message_endpoint(engine, transcoder_id, {:subscribe, endpoint_id, opts})
  end

  @impl true
  def handle_init(ctx, opts) do
    {:endpoint, endpoint_id} = ctx.name

    subscriber = %Subscriber{
      endpoint_id: endpoint_id,
      subscribe_mode: :manual,
      rtc_engine: opts.rtc_engine
    }

    state = %{
      subscriber: subscriber,
      outputs: %{}
    }

    spec = [
      child(:track_data_publisher, TrackDataPublisher)
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
        bin_input(pad)
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
        |> get_child(:track_data_publisher)

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
  def handle_child_notification(
        {:track_data, track_id, data},
        :track_data_publisher,
        _ctx,
        %{subscriber: subscriber} = state
      ) do
    case Subscriber.get_track(subscriber, track_id) do
      nil ->
        {[], state}

      track ->
        {[
           notify_parent:
             {:forward_to_parent, {:track_data, track_id, track.type, track.metadata, data}}
         ], state}
    end
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
  def handle_parent_notification(_msg, _ctx, state) do
    {[], state}
  end

  defp get_decoder(:opus), do: Membrane.Opus.Decoder
  defp get_decoder(_other), do: nil
end
