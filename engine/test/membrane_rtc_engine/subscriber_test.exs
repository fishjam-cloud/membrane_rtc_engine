defmodule Membrane.RTC.SubscriberTest do
  use ExUnit.Case

  alias Membrane.RTC.Engine.Subscriber
  alias Membrane.RTC.Engine.Track

  defmodule MockEngine do
    use GenServer

    @spec start_link(map()) :: {:ok, pid()} | {:error, term()}
    def start_link(tracks) do
      GenServer.start_link(__MODULE__, tracks)
    end

    @impl true
    def init(init_arg) do
      {:ok, init_arg}
    end

    @impl true
    def handle_info({:subscribe, {endpoint_pid, ref}, _endpoint_id, _track_id, _opts}, state) do
      send(endpoint_pid, {ref, :ok, nil})
      {:noreply, state}
    end

    def handle_info({:add_track, track}, state) do
      {:noreply, [track | state]}
    end

    @impl true
    def handle_call(:get_tracks, _from, state) do
      {:reply, state, state}
    end
  end

  test "Manual subscriptions state" do
    track1 = create_track("test1")
    track1_id = track1.id
    track2 = create_track("test2")
    track3 = create_track("test3")
    track3_id = track3.id
    inital_tracks = [track1, track2]

    assert {:ok, mock_engine} = MockEngine.start_link(inital_tracks)

    state = %Subscriber{
      subscribe_mode: :manual,
      endpoint_id: "test-endpoint",
      rtc_engine: mock_engine
    }

    assert %{tracks: %{}} = Subscriber.handle_new_tracks([track1], state)

    assert %{tracks: %{^track1_id => ^track1} = tracks, endpoints: endpoints} =
             state = Subscriber.add_endpoints(["test1"], state)

    endpoints_set = MapSet.new(["test1"])

    assert MapSet.equal?(endpoints, endpoints_set)

    endpoints_set = MapSet.put(endpoints_set, "test3")

    assert %{endpoints: endpoints, tracks: ^tracks} =
             state = Subscriber.add_endpoints(["test3"], state)

    assert MapSet.equal?(endpoints, endpoints_set)

    send(mock_engine, {:add_track, track3})

    assert %{tracks: %{^track1_id => ^track1, ^track3_id => ^track3}} =
             Subscriber.handle_new_tracks([track3], state)
  end

  test "Automatic subscriptions state" do
    track1 = create_track("test1")
    track1_id = track1.id
    track2 = create_track("test2")
    inital_tracks = [track1, track2]

    assert {:ok, mock_engine} = MockEngine.start_link(inital_tracks)

    state = %Subscriber{
      subscribe_mode: :auto,
      endpoint_id: "test-endpoint",
      rtc_engine: mock_engine
    }

    assert %{tracks: %{^track1_id => ^track1}} =
             state = Subscriber.handle_new_tracks([track1], state)

    assert ^state = Subscriber.add_endpoints(["test1"], state)
  end

  test "Track type filtering" do
    video_track = create_track("test1", :video)
    audio_track = create_track("test2", :audio)
    audio_track_id = audio_track.id
    inital_tracks = [video_track, audio_track]

    assert {:ok, mock_engine} = MockEngine.start_link(inital_tracks)

    state = %Subscriber{
      subscribe_mode: :auto,
      endpoint_id: "test-endpoint",
      rtc_engine: mock_engine,
      track_types: [:audio]
    }

    assert ^state = Subscriber.handle_new_tracks([video_track], state)

    state = Subscriber.handle_new_tracks([audio_track], state)
    assert %{tracks: %{^audio_track_id => ^audio_track}} = state
  end

  defp create_track(endpoint_id, :video) do
    Track.new(:video, Track.stream_id(), endpoint_id, :VP8, nil, nil)
  end

  defp create_track(endpoint_id, :audio) do
    Track.new(:audio, Track.stream_id(), endpoint_id, :opus, nil, nil)
  end

  defp create_track(endpoint_id), do: create_track(endpoint_id, :video)
end
