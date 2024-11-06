defmodule WebRTCToHLS.Stream do
  @moduledoc false

  use GenServer

  require Membrane.Logger

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.{HLS, ExWebRTC}
  alias Membrane.RTC.Engine.Endpoint.HLS.{HLSConfig, MixerConfig}
  alias Membrane.RTC.Engine.Message.{EndpointCrashed, EndpointMessage, EndpointRemoved}

  def start(channel_pid, peer_id) do
    GenServer.start(__MODULE__, %{channel_pid: channel_pid, peer_id: peer_id})
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  @impl true
  def init(%{channel_pid: channel_pid, peer_id: peer_id}) do
    Membrane.Logger.info("Spawning room process: #{inspect(self())}")

    rtc_engine_options = [
      id: UUID.uuid4(),
      display_manager?: false
    ]

    {:ok, rtc_engine} = Membrane.RTC.Engine.start(rtc_engine_options, [])

    Engine.register(rtc_engine, self())
    Process.monitor(rtc_engine)
    Process.monitor(channel_pid)

    hls_endpoint = hls_endpoint(rtc_engine)
    webrtc_endpoint = webrtc_endpoint(rtc_engine)

    :ok = Engine.add_endpoint(rtc_engine, hls_endpoint)
    :ok = Engine.add_endpoint(rtc_engine, webrtc_endpoint, id: peer_id)

    {:ok,
     %{
       rtc_engine: rtc_engine,
       channel_pid: channel_pid,
       peer_id: peer_id
     }}
  end

  @impl true
  def handle_info({:playlist_playable, :audio, _playlist_idl}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:playlist_playable, :video, playlist_idl}, state) do
    send(state.channel_pid, {:playlist_playable, playlist_idl})
    {:noreply, state}
  end

  @impl true
  def handle_info(%EndpointMessage{endpoint_id: _to, message: {:media_event, data}}, state) do
    send(state.channel_pid, {:media_event, data})
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %EndpointRemoved{endpoint_id: endpoint_id, endpoint_type: type},
        state
      ) do
    if type == ExWebRTC,
      do: Membrane.Logger.info("Peer #{inspect(endpoint_id)} left RTC Engine"),
      else:
        Membrane.Logger.info(
          "HLS Endpoint #{inspect(endpoint_id)} has been removed from RTC Engine"
        )

    {:noreply, state}
  end

  @impl true
  def handle_info(%EndpointCrashed{endpoint_id: endpoint_id}, state) do
    Membrane.Logger.error("Endpoint #{inspect(endpoint_id)} has crashed!")
    {:noreply, state}
  end

  @impl true
  def handle_info({:media_event, _from, event}, state) do
    Engine.message_endpoint(state.rtc_engine, state.peer_id, {:media_event, event})
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    if pid == state.channel_pid, do: Engine.terminate(state.rtc_engine)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp hls_endpoint(rtc_engine) do
    %HLS{
      rtc_engine: rtc_engine,
      owner: self(),
      mixer_config: %MixerConfig{},
      output_directory:
        Application.fetch_env!(:membrane_webrtc_to_hls_demo, :hls_output_mount_path),
      hls_config: %HLSConfig{cleanup_after: Membrane.Time.second()}
    }
  end

  defp webrtc_endpoint(rtc_engine) do
    ice_port_range =
      Application.fetch_env!(:membrane_webrtc_to_hls_demo, :integrated_turn_port_range)

    %ExWebRTC{
      rtc_engine: rtc_engine,
      ice_port_range: ice_port_range
    }
  end
end
