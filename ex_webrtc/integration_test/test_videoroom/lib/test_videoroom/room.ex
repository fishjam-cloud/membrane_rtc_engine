defmodule TestVideoroom.Room do
  @moduledoc false

  use GenServer

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Message
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC
  require Logger

  def start(opts) do
    GenServer.start(__MODULE__, nil, opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def add_peer_channel(room, peer_channel_pid, peer_id, video_codec) do
    GenServer.call(room, {:add_peer_channel, peer_channel_pid, peer_id, video_codec})
  end

  def register_new_peer_listener(room, listener) do
    GenServer.call(room, {:register_new_peer_listener, listener})
  end

  @impl true
  def init(nil) do
    Logger.info("Spawning room process: #{inspect(self())}")
    
    {:ok, pid} = Membrane.RTC.Engine.start([id: ""], [])
    Process.monitor(pid)
    Engine.register(pid, self())

    {:ok,
     %{
       rtc_engine: pid,
       peer_channels: %{},
       listeners: []
     }}
  end

  @impl true
  def handle_call({:register_new_peer_listener, listener}, _from, state) do
    {:reply, :ok, %{state | listeners: [listener | state.listeners]}}
  end

  @impl true
  def handle_call({:add_peer_channel, peer_channel_pid, peer_id, video_codec}, _from, state) do
    state = put_in(state, [:peer_channels, peer_id], peer_channel_pid)
    Process.monitor(peer_channel_pid)

    endpoint = %ExWebRTC{
      rtc_engine: state.rtc_engine,
      video_codec: video_codec,
      event_serialization: Application.fetch_env!(:test_videoroom, :event_serialization)
    }

    :ok = Engine.add_endpoint(state.rtc_engine, endpoint, id: peer_id)

    for listener <- state.listeners do
      send(listener, {:room, :new_peer})
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(
        %Message.EndpointMessage{endpoint_id: :broadcast, message: {:media_event, data}},
        state
      ) do
    for {_peer_id, pid} <- state.peer_channels, do: send(pid, {:media_event, data})
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message.EndpointMessage{endpoint_id: to, message: {:media_event, data}}, state) do
    if state.peer_channels[to] != nil do
      send(state.peer_channels[to], {:media_event, data})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:media_event, from, event}, state) do
    Engine.message_endpoint(state.rtc_engine, from, {:media_event, event})
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, sfu_pid, _reason}, %{sfu_engine: sfu_pid} = state) do
    {:stop, "rtc engine down", state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {peer_id, _peer_channel_id} =
      state.peer_channels
      |> Enum.find(fn {_peer_id, peer_channel_pid} -> peer_channel_pid == pid end)

    Engine.remove_endpoint(state.rtc_engine, peer_id)
    {_elem, state} = pop_in(state, [:peer_channels, peer_id])
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
