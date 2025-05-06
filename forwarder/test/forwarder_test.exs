defmodule Membrane.RTC.Engine.Endpoint.ForwarderTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  import Membrane.RTC.Engine.Endpoint.Forwarder.TrackHelper

  alias ExWebRTC.PeerConnection
  alias Membrane.RTC.Engine.Endpoint.Forwarder
  alias Membrane.RTC.Engine.Endpoint.Forwarder.WHIPServer
  alias Membrane.Testing.Pipeline

  @stream_id "stream_id"
  @video_codec :h264
  @forwarder_id {:endpoint, "forwarder"}

  setup do
    {pc, server} = WHIPServer.init(@stream_id)
    pipeline = start_pipeline(server)

    on_exit(fn -> WHIPServer.close(server) end)

    {:ok, pipeline: pipeline, pc: pc}
  end

  test "Forwarder subscribes when audio and video tracks are added", %{pipeline: pipeline} do
    new_tracks = [create_track(:audio), create_track(:video)]
    add_new_tracks(pipeline, new_tracks)

    assert_forwarder_subscribe()
    refute_pipeline_crash_group_down(pipeline, :forwarder_group)
  end

  test "Forwarder won`t subscribe when only one track is added", %{pipeline: pipeline} do
    new_tracks = [create_track(:audio)]
    add_new_tracks(pipeline, new_tracks)

    refute_receive {:subscribe, _ref, _endpoint, _track_id, _opts}, 2000

    refute_pipeline_crash_group_down(pipeline, :forwarder_group)
  end

  test "Forwarder won`t crash if there are more than two tracks", %{pipeline: pipeline} do
    new_tracks = [
      create_track(:audio),
      create_track(:audio),
      create_track(:video),
      create_track(:video)
    ]

    add_new_tracks(pipeline, new_tracks)

    assert_forwarder_subscribe()
    refute_pipeline_crash_group_down(pipeline, :forwarder_group)
  end

  test "Forwarder will terminate if one of subscribed tracks will be removed", %{
    pipeline: pipeline
  } do
    new_tracks = [create_track(:audio), create_track(:audio), create_track(:audio)]

    add_new_tracks(pipeline, new_tracks)
    refute_receive {:subscribe, _ref, _endpoint, _track_id, _opts}, 2_000

    remove_tracks(pipeline, [hd(new_tracks)])

    new_tracks = [create_track(:video)]

    add_new_tracks(pipeline, new_tracks)
    assert_forwarder_subscribe()

    remove_tracks(pipeline, new_tracks)
    assert_pipeline_crash_group_down(pipeline, :forwarder_group)
  end

  test "Forwarder will crash if PeerConnection disconnects", %{pipeline: pipeline, pc: pc} do
    new_tracks = [create_track(:audio), create_track(:video)]

    add_new_tracks(pipeline, new_tracks)
    assert_forwarder_subscribe()

    PeerConnection.close(pc)

    assert_pipeline_crash_group_down(pipeline, :forwarder_group, 20_000)
  end

  test "PeerConnection disconnects when Forwarder crashes", %{pipeline: pipeline} do
    new_tracks = [create_track(:audio), create_track(:video)]

    add_new_tracks(pipeline, new_tracks)
    assert_forwarder_subscribe()

    remove_tracks(pipeline, new_tracks)

    assert_pipeline_crash_group_down(pipeline, :forwarder_group)

    assert :ok = WHIPServer.await_disconnect()
  end

  defp add_new_tracks(pipeline, new_tracks) do
    Pipeline.notify_child(pipeline, @forwarder_id, {:new_tracks, new_tracks})
  end

  defp remove_tracks(pipeline, remove_tracks) do
    Pipeline.notify_child(pipeline, @forwarder_id, {:remove_tracks, remove_tracks})
  end

  defp assert_forwarder_subscribe() do
    Enum.each(0..1, fn _idx ->
      assert_receive({:subscribe, {endpoint_pid, ref}, "forwarder", _track_id, _opts}, 2000)
      send(endpoint_pid, {ref, :ok, nil})
    end)

    refute_receive {:subscribe, _ref, _endpoint, _track_id, _opts}
  end

  defp start_pipeline(server) do
    Pipeline.start_link_supervised!(
      spec:
        {[
           child(@forwarder_id, %Forwarder{
             rtc_engine: self(),
             broadcaster_url: WHIPServer.address(server, @stream_id),
             broadcaster_token: "token",
             whip_endpoint: WHIPServer.whip_endpoint(@stream_id),
             video_codec: @video_codec
           })
         ], group: :forwarder_group, crash_group_mode: :temporary}
    )
  end
end
