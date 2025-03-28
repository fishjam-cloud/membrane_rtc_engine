defmodule Membrane.RTC.Engine.Endpoint.RTSP do
  @moduledoc """
  An Endpoint responsible for connecting to a remote RTSP stream source
  and sending the appropriate media track to other Endpoints.

  ## Limitations
  Currently, only H264 streams are supported.

  If the RTSP Endpoint has yet to successfully connect to the stream source,
  a reconnect attempt can be made, either by the endpoint itself,
  or by calling `#{inspect(__MODULE__)}.request_reconnect/2`.
  Once connected, however, if RTSP signalling crashes, the endpoint WILL NOT be able
  to reconnect, and will shut down instead.
  A manual restart of the endpoint will then be needed to restore its functionality.

  Note that the RTSP Endpoint is not guaranteed to work when NAT is used
  by either side of the connection. By default, the endpoint will attempt to
  create client-side NAT binding by sending an empty datagram from client to source,
  after the completion of RTSP setup. This behaviour may be disabled by setting
  the option `:pierce_nat` to `false`.
  """

  use Membrane.Bin

  require Membrane.Logger

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.TrackSender
  alias Membrane.RTC.Engine.Endpoint.RTSP.ConnectionManager
  alias Membrane.RTC.Engine.Track

  @doc """
  Request that a given RTSP Endpoint attempts a reconnect to the remote stream source.
  """
  @spec request_reconnect(rtc_engine :: pid(), endpoint_id :: String.t()) :: :ok
  def request_reconnect(rtc_engine, endpoint_id) do
    Engine.message_endpoint(rtc_engine, endpoint_id, :reconnect)
  end

  @rtp_port 20_000
  @max_reconnect_attempts 3
  @reconnect_delay 15_000
  @keep_alive_interval 15_000
  # Increased buffer size helps ensure the stability of transmission and eliminate video artefacts
  @recv_buffer_size 1024 * 1024

  def_output_pad :output,
    accepted_format: Membrane.RTP,
    availability: :on_request

  def_options rtc_engine: [
                spec: pid(),
                description: "PID of parent Engine"
              ],
              source_uri: [
                spec: URI.t(),
                description: "URI of source stream"
              ],
              rtp_port: [
                spec: 1..65_535,
                description: "Local port RTP stream will be received at",
                default: @rtp_port
              ],
              max_reconnect_attempts: [
                spec: non_neg_integer() | :infinity,
                description: """
                How many times the endpoint will attempt to reconnect before hibernating
                """,
                default: @max_reconnect_attempts
              ],
              reconnect_delay: [
                spec: non_neg_integer(),
                description: "Delay (in ms) between successive reconnect attempts",
                default: @reconnect_delay
              ],
              keep_alive_interval: [
                spec: non_neg_integer(),
                description: """
                Interval (in ms) in which keep-alive RTSP messages will be sent
                to the remote stream source
                """,
                default: @keep_alive_interval
              ],
              pierce_nat: [
                spec: boolean(),
                description: """
                Whether to attempt to create client-side NAT binding by sending
                an empty datagram from client to source, after the completion of RTSP setup
                """,
                default: true
              ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      rtc_engine: opts.rtc_engine,
      source_uri: opts.source_uri,
      rtp_port: opts.rtp_port,
      track: nil,
      ssrc: nil,
      connection_manager: nil,
      pierce_nat: opts.pierce_nat
    }

    connection_manager_opts = [
      stream_uri: state.source_uri,
      port: state.rtp_port,
      endpoint: self(),
      max_reconnect_attempts: opts.max_reconnect_attempts,
      reconnect_delay: opts.reconnect_delay,
      keep_alive_interval: opts.keep_alive_interval
    ]

    {:ok, pid} = ConnectionManager.start_link(connection_manager_opts)

    {[notify_parent: :ready], %{state | connection_manager: pid}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {track_id, :high}) = pad, _ctx, state)
      when track_id == state.track.id do
    Membrane.Logger.debug("Pad added for track #{inspect(track_id)}, variant :high")

    {spss, ppss} =
      case Map.get(state.track.fmtp, :sprop_parameter_sets) do
        nil -> {[], []}
        %{sps: sps, pps: pps} -> {[sps], [pps]}
      end

    spec = [
      get_child(:rtp)
      |> via_out(Pad.ref(:output, state.ssrc),
        options: [depayloader: Membrane.RTP.H264.Depayloader]
      )
      |> child(:parser, %Membrane.H264.Parser{
        spss: spss,
        ppss: ppss,
        output_alignment: :nalu,
        output_stream_structure: :annexb,
        skip_until_keyframe: true,
        repeat_parameter_sets: true
      })
      |> child(:payloader, %Membrane.RTP.PayloaderBin{
        payloader: Membrane.RTP.H264.Payloader,
        ssrc: state.ssrc,
        payload_type: state.track.ctx.rtpmap.payload_type,
        clock_rate: state.track.ctx.rtpmap.clock_rate
      })
      |> via_in(Pad.ref(:input, {track_id, :high}))
      |> child(
        {:track_sender, track_id},
        %TrackSender{
          track: state.track,
          variant_bitrates: %{},
          is_keyframe_fun: fn buf, :H264 ->
            Membrane.RTP.H264.Utils.keyframe?(buf.payload, :idr)
          end
        }
      )
      |> via_out(pad)
      |> bin_output(pad)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:output, {_track_id, _variant}), _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification(:reconnect, _ctx, state) do
    Membrane.Logger.info("Attempting reconnect to remote RTSP stream source...")

    ConnectionManager.reconnect(state.connection_manager)
    {[], state}
  end

  @impl true
  def handle_parent_notification({:new_tracks, _tracks}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification({:remove_tracks, _tracks}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification(msg, _ctx, state) do
    Membrane.Logger.warning("Unexpected message: #{inspect(msg)}. Ignoring.")
    {[], state}
  end

  @impl true
  def handle_child_notification(
        {:new_rtp_stream, ssrc, fmt, _extensions} = msg,
        :rtp,
        _ctx,
        state
      )
      when is_nil(state.ssrc) or ssrc == state.ssrc do
    Membrane.Logger.debug("New RTP stream connected: #{inspect(msg)}")

    state = %{state | ssrc: ssrc}

    expected_fmt = state.track.ctx.rtpmap.payload_type

    if fmt != expected_fmt do
      raise("""
      Payload type mismatch between RTP mapping and received stream
      (expected #{inspect(expected_fmt)}, got #{inspect(fmt)})
      """)
    end

    {[
       notify_parent: {:forward_to_parent, :new_rtp_stream},
       notify_parent: {:track_ready, state.track.id, :high, state.track.encoding}
     ], state}
  end

  @impl true
  def handle_child_notification(
        {:new_rtp_stream, _ssrc, _fmt, _extensions} = msg,
        :rtp,
        _ctx,
        _state
      ) do
    raise("Received unexpected, second RTP stream: #{inspect(msg)}")
  end

  @impl true
  def handle_child_notification({:connection_info, _address, _port}, :udp_source, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_notification({:estimation, _data}, {:track_sender, _track_id}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_notification(notification, element, _ctx, state) do
    Membrane.Logger.warning(
      "Unexpected notification from `#{inspect(element)}`: #{inspect(notification)}. Ignoring."
    )

    {[], state}
  end

  @impl true
  def handle_info({:rtsp_setup_complete, options}, ctx, state) do
    Membrane.Logger.debug("Endpoint received source options: #{inspect(options)}")

    rtpmap = options.rtpmap

    if rtpmap.encoding != "H264" do
      raise("RTSP setup returned unsupported stream encoding: #{inspect(rtpmap.encoding)}")
    end

    {:endpoint, endpoint_id} = ctx.name

    track =
      Track.new(
        :video,
        Track.stream_id(),
        endpoint_id,
        :H264,
        rtpmap.clock_rate,
        options.fmtp,
        ctx: %{rtpmap: rtpmap}
      )

    Membrane.Logger.debug("Publishing new RTSP track: #{inspect(track)}")

    pierce_nat_ctx =
      if state.pierce_nat, do: %{uri: state.source_uri, port: options.server_port}, else: nil

    spec = [
      child(:udp_source, %Membrane.UDP.Source{
        local_port_no: state.rtp_port,
        pierce_nat_ctx: pierce_nat_ctx,
        recv_buffer_size: @recv_buffer_size
      })
      |> via_in(Pad.ref(:rtp_input, make_ref()))
      |> child(:rtp, %Membrane.RTP.SessionBin{
        fmt_mapping: %{rtpmap.payload_type => {:H264, rtpmap.clock_rate}}
      })
    ]

    actions = [
      spec: spec,
      notify_parent: {:forward_to_parent, :rtsp_setup_complete},
      notify_parent: {:publish, {:new_tracks, [track]}}
    ]

    state = %{state | track: track}

    {actions, state}
  end

  @impl true
  def handle_info({:connection_info, {:connection_failed, reason} = msg}, _ctx, state) do
    Membrane.Logger.warning("RTSP Endpoint: Connection failed: #{inspect(reason)}")

    if reason == :invalid_url do
      raise("RTSP Endpoint: Invalid URI. Endpoint shutting down")
    end

    {[notify_parent: {:forward_to_parent, msg}], state}
  end

  @impl true
  def handle_info({:connection_info, :max_reconnects}, _ctx, state) do
    Membrane.Logger.warning("RTSP Endpoint: Max reconnect attempts reached.")
    {[notify_parent: {:forward_to_parent, :max_reconnects}], state}
  end

  @impl true
  def handle_info({:connection_info, :disconnected}, _ctx, state) do
    Membrane.Logger.error("""
    RTSP Endpoint disconnected from source.
    The endpoint is now functionally useless, it will not be able to reconnect and is thus shutting down
    """)

    {[notify_parent: {:forward_to_parent, :disconnected}, terminate: :shutdown], state}
  end

  @impl true
  def handle_info(info, _ctx, state) do
    Membrane.Logger.warning("Unexpected info: #{inspect(info)}. Ignoring.")
    {[], state}
  end
end
