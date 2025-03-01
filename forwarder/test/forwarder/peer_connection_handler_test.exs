defmodule Membrane.RTC.Engine.Endpoint.Forwarder.PeerConnectionHandlerTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  import Membrane.RTC.Engine.Endpoint.Forwarder.TrackHelper

  alias Membrane.RTC.Engine.Endpoint.Forwarder.{PeerConnectionHandler, WHIPServer}
  alias Membrane.Testing.Pipeline

  @endpoint_id "forwarder_endpoint"

  test "peers adds an audio and video tracks" do
    server = WHIPServer.init()
    pipeline = start_pipeline(server)

    tracks = %{video: create_track(:video), audio: create_track(:audio)}

    Pipeline.notify_child(pipeline, :handler, {:start_negotiation, tracks})

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)
  end

  test "whip server returns error on sdp offer" do
    server = WHIPServer.init(offer: false, ice: false)
    pipeline = start_pipeline(server)

    tracks = %{video: create_track(:video), audio: create_track(:audio)}

    Pipeline.notify_child(pipeline, :handler, {:start_negotiation, tracks})

    assert_pipeline_crash_group_down(pipeline, :handler_group)
  end

  test "whip server returns error on ice candidate" do
    server = WHIPServer.init(ice: false)
    pipeline = start_pipeline(server)

    tracks = %{video: create_track(:video), audio: create_track(:audio)}

    Pipeline.notify_child(pipeline, :handler, {:start_negotiation, tracks})

    assert_pipeline_notified(pipeline, :handler, :negotiation_done)
  end

  defp start_pipeline(server) do
    Pipeline.start_link_supervised!(
      spec:
        {[
           child(:handler, %PeerConnectionHandler{
             endpoint_id: @endpoint_id,
             broadcaster_url: WHIPServer.address(server),
             broadcaster_token: "token"
           })
         ], group: :handler_group, crash_group_mode: :temporary}
    )
  end
end
