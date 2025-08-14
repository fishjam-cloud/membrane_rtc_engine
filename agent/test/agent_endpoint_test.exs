defmodule Membrane.RTC.Engine.Endpoint.AgentEndpointTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.File
  alias Membrane.RTC.Engine.Endpoint.Agent
  alias Membrane.RTC.Engine.Support.FakeSourceEndpoint
  alias Membrane.RTC.Engine.Track

  @fixtures_dir "./test/fixtures/"
  @opus_mono_path Path.join(@fixtures_dir, "mono.ogg")
  @opus_stereo_path Path.join(@fixtures_dir, "stereo.ogg")

  setup do
    {:ok, engine} = Engine.start_link([id: "test_rtc"], [])
    :ok = Engine.register(engine, self())

    on_exit(fn -> Engine.terminate(engine) end)

    %{rtc_engine: engine}
  end

  test "Agent adds tracks of subscribed endpoints", %{rtc_engine: engine} do
    agent_endpoint = create_agent_endpoint(engine)
    mono_endpoint = create_file_endpoint(engine, @opus_mono_path)
    stereo_endpoint = create_file_endpoint(engine, @opus_stereo_path)

    :ok = Engine.add_endpoint(engine, agent_endpoint, id: "agent")
    :ok = Engine.add_endpoint(engine, mono_endpoint, id: :mono_sender)
    :ok = Engine.add_endpoint(engine, stereo_endpoint, id: :stereo_sender)

    :ok =
      Agent.subscribe(engine, "agent", :mono_sender, format: :pcm16, sample_rate: 16_000)

    :ok =
      Agent.subscribe(engine, "agent", :stereo_sender,
        format: :pcm16,
        sample_rate: 24_000
      )

    assert_receive %Engine.Message.TrackAdded{
                     endpoint_id: :mono_sender,
                     track_id: mono_track_id,
                     track_metadata: mono_metadata
                   },
                   1000

    assert_receive %Engine.Message.TrackAdded{
                     endpoint_id: :stereo_sender,
                     track_id: stereo_track_id,
                     track_metadata: stereo_metadata
                   },
                   1000

    assert_receive %Engine.Message.EndpointMessage{
                     endpoint_id: "agent",
                     endpoint_type: Agent,
                     message:
                       {:track_data, :mono_sender, ^mono_track_id, :audio, ^mono_metadata, _data}
                   },
                   1000

    assert_receive %Engine.Message.EndpointMessage{
                     endpoint_id: "agent",
                     endpoint_type: Agent,
                     message:
                       {:track_data, :stereo_sender, ^stereo_track_id, :audio, ^stereo_metadata,
                        _data}
                   },
                   1000
  end

  test "Agent ignores tracks of unsubscribed endpoints", %{rtc_engine: engine} do
    agent_endpoint = create_agent_endpoint(engine)
    mono_endpoint = create_file_endpoint(engine, @opus_mono_path)

    :ok = Engine.add_endpoint(engine, agent_endpoint, id: "agent")
    :ok = Engine.add_endpoint(engine, mono_endpoint, id: :mono_sender)

    assert_receive %Engine.Message.TrackAdded{
                     endpoint_id: :mono_sender,
                     track_id: mono_track_id,
                     track_metadata: mono_metadata
                   },
                   1000

    refute_receive %Engine.Message.EndpointMessage{
                     endpoint_id: "agent",
                     endpoint_type: Agent,
                     message:
                       {:track_data, :mono_sender, ^mono_track_id, :audio, ^mono_metadata, _data}
                   },
                   1000
  end

  test "Agent removes subscription when endpoint removed", %{rtc_engine: engine} do
    agent_endpoint = create_agent_endpoint(engine)
    mono_endpoint = create_file_endpoint(engine, @opus_mono_path)

    :ok = Engine.add_endpoint(engine, agent_endpoint, id: "agent")
    :ok = Engine.add_endpoint(engine, mono_endpoint, id: :mono_sender)

    :ok =
      Agent.subscribe(engine, "agent", :mono_sender,
        format: :pcm16,
        sample_rate: 16_000
      )

    assert_receive %Engine.Message.TrackAdded{
                     endpoint_id: :mono_sender,
                     track_id: mono_track_id,
                     track_metadata: mono_metadata
                   },
                   1000

    assert_receive %Engine.Message.EndpointMessage{
                     endpoint_id: "agent",
                     endpoint_type: Agent,
                     message:
                       {:track_data, :mono_sender, ^mono_track_id, :audio, ^mono_metadata, _data}
                   },
                   1000

    assert capture_log(fn ->
             :ok = Engine.remove_endpoint(engine, :mono_sender)
             Process.sleep(1000)
           end) =~ "Removed subscription for endpoint :mono_sender"

    refute_receive %Engine.Message.EndpointCrashed{}, 1000
  end

  test "Agent ignores video tracks", %{rtc_engine: engine} do
    agent_endpoint = create_agent_endpoint(engine)
    track = Track.new(:video, Track.stream_id(), :test_endpoint, :H264, 90_000, nil)
    test_endpoint = %FakeSourceEndpoint{rtc_engine: engine, track: track}

    Engine.add_endpoint(engine, agent_endpoint, id: "agent")
    Engine.add_endpoint(engine, test_endpoint, id: :test_endpoint)
    Engine.message_endpoint(engine, :test_endpoint, :start)

    assert not (capture_log([level: :debug], fn ->
                  Agent.subscribe(engine, "agent", :test_endpoint,
                    format: :pcm16,
                    sample_rate: 24_000
                  )

                  Process.sleep(1_000)
                end) =~ "Subscription fulfilled by agent on track: #{track.id}")
  end

  defp create_agent_endpoint(rtc_engine) do
    %Agent{rtc_engine: rtc_engine}
  end

  defp create_file_endpoint(rtc_engine, file_path) do
    track_config = %File.TrackConfig{
      type: :audio,
      encoding: :opus,
      clock_rate: 48_000,
      fmtp: %ExSDP.Attribute.FMTP{pt: 108}
    }

    %File{
      rtc_engine: rtc_engine,
      file_path: file_path,
      track_config: track_config,
      payload_type: 108
    }
  end
end
