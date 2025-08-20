defmodule Membrane.RTC.Engine.Endpoint.AgentEndpointTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Membrane.ChildrenSpec

  alias Membrane.Testing

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.{Agent, File}
  alias Membrane.RTC.Engine.Endpoint.Agent.Test.BufferForwarder
  alias Membrane.RTC.Engine.Support.{FakeSourceEndpoint, TestSinkEndpoint}
  alias Membrane.RTC.Engine.Track

  alias Fishjam.AgentRequest
  alias Fishjam.AgentRequest.AddTrack
  alias Fishjam.AgentRequest.AddTrack.CodecParameters
  alias Fishjam.Notifications

  alias Fishjam.AgentResponse.TrackData

  @fixtures_dir "./test/fixtures/"
  @opus_mono_path Path.join(@fixtures_dir, "mono.ogg")
  @opus_stereo_path Path.join(@fixtures_dir, "stereo.ogg")
  @raw_audio_file Path.join(@fixtures_dir, "pcm_mono_16k.raw")
  @raw_audio_sample_rate 16_000
  @opus_sample_rate 48_000

  @agent_id "agent"
  @input_track_id "34a75983-7c45-49db-9e6a-3d776ec3a39d"

  setup do
    {:ok, engine} = Engine.start_link([id: "test_rtc"], [])
    :ok = Engine.register(engine, self())

    on_exit(fn -> Engine.terminate(engine) end)

    %{rtc_engine: engine}
  end

  describe "Publishing track data" do
    test "Agent adds tracks of subscribed endpoints", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      mono_endpoint = create_file_endpoint(engine, @opus_mono_path)
      stereo_endpoint = create_file_endpoint(engine, @opus_stereo_path)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, mono_endpoint, id: :mono_sender)
      :ok = Engine.add_endpoint(engine, stereo_endpoint, id: :stereo_sender)

      :ok =
        Agent.subscribe(engine, "agent", :mono_sender, format: :pcm16, sample_rate: 16_000)

      :ok =
        Agent.subscribe(engine, @agent_id, :stereo_sender,
          format: :pcm16,
          sample_rate: 24_000
        )

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: :mono_sender,
                       track_id: mono_track_id,
                       track_metadata: nil
                     },
                     1000

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: :stereo_sender,
                       track_id: stereo_track_id,
                       track_metadata: nil
                     },
                     1000

      assert_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          {:track_data,
                           %TrackData{
                             peer_id: @agent_id,
                             track: %Notifications.Track{
                               id: ^mono_track_id,
                               type: :TRACK_TYPE_AUDIO,
                               metadata: "null"
                             },
                             data: _data
                           }}}
                     },
                     1000

      assert_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          {:track_data,
                           %TrackData{
                             peer_id: @agent_id,
                             track: %Notifications.Track{
                               id: ^stereo_track_id,
                               type: :TRACK_TYPE_AUDIO,
                               metadata: "null"
                             },
                             data: _data
                           }}}
                     },
                     1000
    end

    test "Agent ignores tracks of unsubscribed endpoints", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      mono_endpoint = create_file_endpoint(engine, @opus_mono_path)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, mono_endpoint, id: :mono_sender)

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: :mono_sender,
                       track_id: mono_track_id,
                       track_metadata: mono_metadata
                     },
                     1000

      refute_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          {:track_data,
                           %TrackData{
                             peer_id: @agent_id,
                             track: %Notifications.Track{
                               id: ^mono_track_id,
                               type: :TRACK_TYPE_AUDIO,
                               metadata: ^mono_metadata
                             },
                             data: _data
                           }}}
                     },
                     1000
    end

    test "Agent removes subscription when endpoint removed", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      mono_endpoint = create_file_endpoint(engine, @opus_mono_path)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, mono_endpoint, id: :mono_sender)

      :ok =
        Agent.subscribe(engine, "agent", :mono_sender,
          format: :pcm16,
          sample_rate: 16_000
        )

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: :mono_sender,
                       track_id: mono_track_id,
                       track_metadata: nil
                     },
                     1000

      assert_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          {:track_data,
                           %TrackData{
                             peer_id: @agent_id,
                             track: %Notifications.Track{
                               id: ^mono_track_id,
                               type: :TRACK_TYPE_AUDIO,
                               metadata: "null"
                             },
                             data: _data
                           }}}
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

      Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
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
  end

  describe "Forwarding track data" do
    test "Creates correct engine track ", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)

      start_raw_audio_pipeline(engine)

      assert_receive %Engine.Message.TrackAdded{
        endpoint_id: @agent_id,
        track_id: @input_track_id,
        track_metadata: %{"name" => "It's a track", "source" => "macbook camera"},
        track_type: :audio,
        track_encoding: :opus
      }

      refute_receive %Engine.Message.EndpointCrashed{}, 1000
    end

    test "Publishes pcm16 track to other endpoints", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      sink1 = create_sink_endpoint("sink1", engine)
      sink2 = create_sink_endpoint("sink2", engine)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, sink1, id: "sink1")
      :ok = Engine.add_endpoint(engine, sink2, id: "sink2")

      start_raw_audio_pipeline(engine)

      assert_receive %Engine.Message.TrackAdded{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      assert count_sink_buffers("sink1") > 50
      assert count_sink_buffers("sink2") > 50

      assert_receive %Engine.Message.TrackRemoved{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      refute_receive %Engine.Message.EndpointCrashed{}, 1000
    end

    test "Publishes opus track to other endpoints", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      sink1 = create_sink_endpoint("sink1", engine)
      sink2 = create_sink_endpoint("sink2", engine)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, sink1, id: "sink1")
      :ok = Engine.add_endpoint(engine, sink2, id: "sink2")

      start_opus_audio_pipeline(engine)

      assert_receive %Engine.Message.TrackAdded{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      assert count_sink_buffers("sink1") > 50
      assert count_sink_buffers("sink2") > 50

      assert_receive %Engine.Message.TrackRemoved{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      refute_receive %Engine.Message.EndpointCrashed{}, 1000
    end

    test "Invalid codec params", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)

      add_track = %AddTrack{
        track: %Notifications.Track{
          id: @input_track_id,
          type: :TRACK_TYPE_AUDIO,
          metadata: ""
        },
        codec_params: %CodecParameters{
          encoding: :TRACK_ENCODING_PCM16,
          sample_rate: 2137,
          channels: 1
        }
      }

      request = %AgentRequest{content: {:add_track, add_track}}

      Engine.message_endpoint(engine, @agent_id, {:agent_notification, request})

      assert_receive %Engine.Message.EndpointCrashed{
                       endpoint_id: @agent_id,
                       reason: {%RuntimeError{message: message}, _stack}
                     },
                     1000

      assert message =~ "AddTrack request with invalid codec params"
    end

    test "Invalid track_id", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)

      add_track = %AddTrack{
        track: %Notifications.Track{
          id: "defninitely-not-uuid",
          type: :TRACK_TYPE_AUDIO,
          metadata: ""
        },
        codec_params: %CodecParameters{
          encoding: :TRACK_ENCODING_PCM16,
          sample_rate: 24_000,
          channels: 1
        }
      }

      request = %AgentRequest{content: {:add_track, add_track}}

      Engine.message_endpoint(engine, @agent_id, {:agent_notification, request})

      assert_receive %Engine.Message.EndpointCrashed{
                       endpoint_id: @agent_id,
                       reason: {%RuntimeError{message: message}, _stack}
                     },
                     1000

      assert message =~ "AddTrack request with invalid track_id"
    end
  end

  defp create_agent_endpoint(engine) do
    %Agent{rtc_engine: engine}
  end

  defp create_sink_endpoint(name, engine) do
    test_process_pid = self()

    handle_buffer = &send(test_process_pid, {:sink_buffer, name, &1})

    %TestSinkEndpoint{rtc_engine: engine, owner: self(), handle_buffer: handle_buffer}
  end

  defp count_sink_buffers(name, count \\ 0) do
    receive do
      {:sink_buffer, ^name, %Membrane.Buffer{payload: payload}}
      when is_binary(payload) ->
        count_sink_buffers(name, count + 1)
    after
      100 -> count
    end
  end

  defp create_file_endpoint(engine, file_path) do
    track_config = %File.TrackConfig{
      type: :audio,
      encoding: :opus,
      clock_rate: 48_000,
      fmtp: %ExSDP.Attribute.FMTP{pt: 108}
    }

    %File{
      rtc_engine: engine,
      file_path: file_path,
      track_config: track_config,
      payload_type: 108
    }
  end

  defp start_raw_audio_pipeline(engine) do
    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:file_source, %Membrane.File.Source{location: @raw_audio_file})
        |> child(:parser, %Membrane.RawAudioParser{
          stream_format: %Membrane.RawAudio{
            channels: 1,
            sample_rate: @raw_audio_sample_rate,
            sample_format: :s16le
          }
        })
        |> child(:buffer_forwarder, %BufferForwarder{
          rtc_engine: engine,
          sample_rate: @raw_audio_sample_rate,
          encoding: :pcm16,
          track_id: @input_track_id
        })
      ]
    )
  end

  defp start_opus_audio_pipeline(engine) do
    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:file_source, %Membrane.File.Source{location: @opus_mono_path})
        |> child(:ogg_demuxer, Membrane.Ogg.Demuxer)
        |> child(:opus_parser, %Membrane.Opus.Parser{generate_best_effort_timestamps?: true})
        |> child(:buffer_forwarder, %BufferForwarder{
          rtc_engine: engine,
          sample_rate: @opus_sample_rate,
          encoding: :opus,
          track_id: @input_track_id
        })
      ]
    )
  end
end
