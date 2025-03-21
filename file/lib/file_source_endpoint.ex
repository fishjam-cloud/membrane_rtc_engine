defmodule Membrane.RTC.Engine.Endpoint.File do
  @moduledoc """
  An Endpoint responsible for publishing data from a file.
  By default only supports OPUS encapsulated in Ogg container and raw H264 files.
  By providing proper value in option `after_source_transformation` you can read other formats, but the output from `after_source_transformation` have to be encoded in OPUS or H264.
  It can start publishing data in three different moments:
  * immediately after initialization, if `playback_mode` is set to `:autoplay` (default),
  * after calling `playback_mode` function with proper arguments, if `playback_mode` is set to `:manual`
  * after other endpoint subscribes on this endpoint track, if `playback_mode` is set to `:wait_for_first_subscriber`
  Currently, the File Endpoint only supports files that contain a single media track.
  """

  use Membrane.Bin

  require Membrane.Logger

  alias Membrane.ChildrenSpec
  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.File.TrackConfig
  alias Membrane.RTC.Engine.Support.StaticTrackSender
  alias Membrane.RTC.Engine.Track
  alias Membrane.RTP
  alias Membrane.RTP.PayloaderBin

  @type encoding_t() :: String.t()

  @toilet_capacity 1_000

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ],
              file_path: [
                spec: Path.t(),
                description: "Path to track file"
              ],
              track_config: [
                spec: TrackConfig.t(),
                description: "Configuration of the track being published"
              ],
              ssrc: [
                spec: RTP.ssrc(),
                description: "SSRC of RTP packets",
                default: nil
              ],
              payload_type: [
                spec: RTP.payload_type(),
                description: "Payload type of RTP packets"
              ],
              playback_mode: [
                spec: :autoplay | :manual | :wait_for_first_subscriber,
                default: :autoplay,
                description: """
                Indicates, when the endpoint should start sending data:
                * autoplay - start immediately after initialization
                * manual - start on calling `start_sending/2` function
                * wait_for_first_subscriber - start when the first endpoint subscribes on the track
                """
              ],
              # Addded because current implementation of Membrane don't guarantee
              # that other endpoints which subscribes on track from this endpoint
              # will be able to process safely all data from this endpoints.
              autoend: [
                spec: boolean(),
                default: true,
                description: "Indicates, whether the endpoint should send `:finished`
                notification to engine immediately after processing all data. If set to `false`,
                the endpoint hast to be removed manually.
                "
              ],
              after_source_transformation: [
                spec: (ChildrenSpec.builder() -> ChildrenSpec.builder()),
                default: &Function.identity/1,
                description: """
                Additional pipeline transformation after `file_source`.
                The output stream must be encoded in OPUS or H264.

                Use this option when the provided file uses encoding other than
                Ogg encapsulated OPUS audio or H264 video.

                Example usage:
                * Reading ACC file: `fn link_builder ->  link_builder
                |> child(:decoder, Membrane.AAC.FDK.Decoder)
                |> child(:encoder, %Membrane.Opus.Encoder{input_stream_format:
                %Membrane.RawAudio{ channels: 1, sample_rate: 48_000, sample_format: :s16le }}) end`
                """
              ]

  def_output_pad :output,
    accepted_format: Membrane.RTP,
    availability: :on_request

  @spec start_sending(pid(), any()) :: :ok
  def start_sending(engine, endpoint_id) do
    Engine.message_endpoint(engine, endpoint_id, :start)
  end

  @impl true
  def handle_init(ctx, opts) do
    unless Enum.any?([:H264, :opus], &(&1 == opts.track_config.encoding)) do
      raise "Unsupported track codec: #{inspect(opts.track_config.encoding)}. The only supported codecs are :H264 and :opus."
    end

    {:endpoint, endpoint_id} = ctx.name

    track =
      Track.new(
        opts.track_config.type,
        opts.track_config.stream_id || Track.stream_id(),
        endpoint_id,
        opts.track_config.encoding,
        opts.track_config.clock_rate,
        opts.track_config.fmtp,
        opts.track_config.opts
      )

    state =
      Map.from_struct(opts)
      |> Map.drop([:track_config])
      |> Map.merge(%{
        track: track,
        ssrc: opts.ssrc || new_ssrc(),
        started: false
      })

    {[notify_parent: :ready], state}
  end

  @impl true
  def handle_playing(_ctx, %{playback_mode: :manual} = state) do
    {get_new_tracks_actions(state), state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    actions = get_new_tracks_actions(state) ++ get_track_ready_notification(state)

    {actions, %{state | started: true}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {_track_id, _rid}) = pad, _ctx, state) do
    actions =
      if state.track.encoding == :opus and
           state.after_source_transformation == (&Function.identity/1) do
        build_pipeline_ogg_demuxer(state, pad)
      else
        build_full_pipeline(state, pad)
      end

    {actions, state}
  end

  @impl true
  def handle_element_end_of_stream(:track_sender, _pad, _ctx, state) do
    actions =
      if state.autoend,
        do: [
          notify_parent: {:publish, {:removed_tracks, [state.track]}},
          notify_parent: :finished
        ],
        else: []

    {actions, state}
  end

  @impl true
  def handle_element_end_of_stream(_other, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification({:ready, _other_endpoints}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification({:new_endpoint, _endpoint}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification({:endpoint_removed, _endpoint_id}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification({:new_tracks, _list}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification({:remove_tracks, _list}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification(:start, _ctx, %{playback_mode: playback_mode} = state)
      when playback_mode != :manual do
    Membrane.Logger.warning(
      "Trying to manually start sending media in `playback_mode` mode different than :manual"
    )

    {[], state}
  end

  @impl true
  def handle_parent_notification(:start, _ctx, %{started: true} = state) do
    Membrane.Logger.warning("Trying to manually start sending media when already started")
    {[], state}
  end

  @impl true
  def handle_parent_notification(:start, _ctx, state) do
    {get_track_ready_notification(state), %{state | started: true}}
  end

  defp get_track_ready_notification(state) do
    [notify_parent: {:track_ready, state.track.id, :high, state.track.encoding}]
  end

  defp get_new_tracks_actions(state) do
    [
      notify_parent: {:publish, {:new_tracks, [state.track]}},
      notify_parent: {:forward_to_parent, :tracks_added}
    ]
  end

  defp build_pipeline_ogg_demuxer(state, pad) do
    spec = [
      child(:source, %Membrane.File.Source{location: state.file_path})
      |> child(:ogg_demuxer, Membrane.Ogg.Demuxer)
      |> child(:opus_parser, opus_parser())
      |> then(get_rest_of_pipeline(state, pad))
    ]

    [spec: spec]
  end

  defp build_full_pipeline(state, pad) do
    spec = [
      child(:source, %Membrane.File.Source{location: state.file_path})
      |> then(&state.after_source_transformation.(&1))
      |> then(get_parser(state.track))
      |> then(get_rest_of_pipeline(state, pad))
    ]

    [spec: spec]
  end

  defp get_rest_of_pipeline(state, pad) do
    payloader = Membrane.RTP.PayloadFormat.get(state.track.encoding).payloader

    payloader_bin = %PayloaderBin{
      payloader: payloader,
      ssrc: state.ssrc,
      payload_type: state.payload_type,
      clock_rate: state.track.clock_rate
    }

    fn link_builder ->
      link_builder
      |> child(:payloader, payloader_bin)
      |> via_in(:input, toilet_capacity: @toilet_capacity)
      |> child(:realtimer, Membrane.Realtimer)
      |> via_in(:input, toilet_capacity: @toilet_capacity)
      |> child(:track_sender, %StaticTrackSender{
        track: state.track,
        is_keyframe: fn buffer, track ->
          case track.encoding do
            :opus -> true
            :H264 -> Membrane.RTP.H264.Utils.keyframe?(buffer.payload)
          end
        end,
        wait_for_keyframe_request?: state.playback_mode == :wait_for_first_subscriber
      })
      |> bin_output(pad)
    end
  end

  defp get_parser(%Track{encoding: :opus}) do
    fn link_builder ->
      child(link_builder, :parser, opus_parser())
    end
  end

  defp get_parser(%Track{encoding: :H264, framerate: framerate}) do
    fn link_builder ->
      child(link_builder, :parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{
          framerate: framerate
        },
        output_alignment: :nalu
      })
    end
  end

  defp opus_parser(), do: %Membrane.Opus.Parser{generate_best_effort_timestamps?: true}

  defp new_ssrc() do
    :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned()
  end
end
