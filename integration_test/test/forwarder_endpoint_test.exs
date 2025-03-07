defmodule Membrane.RTC.ForwarderEndpointTest do
  use ExUnit.Case

  import FileEndpointGenerator

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.Forwarder
  alias Membrane.RTC.Engine.Endpoint.Forwarder.WHIPServer
  alias Membrane.RTC.Engine.Message

  @stream_id "stream_id"
  @forwarder_id "forwarder"

  @fixtures_dir "./test/fixtures/"
  @audio_file_path Path.join(@fixtures_dir, "audio.aac")
  @video_file_path Path.join(@fixtures_dir, "video.h264")

  @tracks_added_delay 500

  setup do
    {_pc, server} = WHIPServer.init(@stream_id)
    {:ok, pid} = Engine.start_link([id: "test_rtc"], [])

    Engine.register(pid, self())

    on_exit(fn ->
      Engine.terminate(pid)
    end)

    {:ok, rtc_engine: pid, server: server}
  end

  test "Sends media when there is single audio and video track", %{
    rtc_engine: rtc_engine,
    server: server
  } do
    forwarder_endpoint = create_forwarder_endpoint(rtc_engine, server)
    :ok = Engine.add_endpoint(rtc_engine, forwarder_endpoint, id: @forwarder_id)

    audio_file_endpoint = create_audio_file_endpoint(rtc_engine, @audio_file_path)
    video_file_endpoint = create_video_file_endpoint(rtc_engine, @video_file_path)

    :ok = Engine.add_endpoint(rtc_engine, audio_file_endpoint)
    :ok = Engine.add_endpoint(rtc_engine, video_file_endpoint)

    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay
    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay

    assert WHIPServer.receive_media?()
  end

  test "Sends media when there are multiple audio and video tracks", %{
    rtc_engine: rtc_engine,
    server: server
  } do
    forwarder_endpoint = create_forwarder_endpoint(rtc_engine, server)
    :ok = Engine.add_endpoint(rtc_engine, forwarder_endpoint, id: @forwarder_id)

    audio_file_endpoint_1 = create_audio_file_endpoint(rtc_engine, @audio_file_path)
    audio_file_endpoint_2 = create_audio_file_endpoint(rtc_engine, @audio_file_path)
    video_file_endpoint_1 = create_video_file_endpoint(rtc_engine, @video_file_path)
    video_file_endpoint_2 = create_video_file_endpoint(rtc_engine, @video_file_path)

    :ok = Engine.add_endpoint(rtc_engine, audio_file_endpoint_1)
    :ok = Engine.add_endpoint(rtc_engine, audio_file_endpoint_2)
    :ok = Engine.add_endpoint(rtc_engine, video_file_endpoint_1)
    :ok = Engine.add_endpoint(rtc_engine, video_file_endpoint_2)

    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay
    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay
    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay
    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay

    assert WHIPServer.receive_media?()
  end

  test "Doesn't send media when there is only one type of track", %{
    rtc_engine: rtc_engine,
    server: server
  } do
    forwarder_endpoint = create_forwarder_endpoint(rtc_engine, server)
    :ok = Engine.add_endpoint(rtc_engine, forwarder_endpoint, id: @forwarder_id)

    audio_file_endpoint_1 = create_audio_file_endpoint(rtc_engine, @audio_file_path)
    audio_file_endpoint_2 = create_audio_file_endpoint(rtc_engine, @audio_file_path)

    :ok = Engine.add_endpoint(rtc_engine, audio_file_endpoint_1)
    :ok = Engine.add_endpoint(rtc_engine, audio_file_endpoint_2)

    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay
    assert_receive %Message.EndpointMessage{message: :tracks_added}, @tracks_added_delay

    assert not WHIPServer.receive_media?()
  end

  defp create_forwarder_endpoint(rtc_engine, server) do
    %Forwarder{
      rtc_engine: rtc_engine,
      broadcaster_url: WHIPServer.address(server, @stream_id),
      broadcaster_token: "token",
      stream_id: @stream_id
    }
  end
end
