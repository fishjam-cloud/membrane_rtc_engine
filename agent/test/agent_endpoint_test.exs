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
  @second_input_track_id "2d392628-a315-4a35-9543-226d74d9f940"

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
      mono_endpoint_id = "mono_endpoint"
      stereo_endpoint = create_file_endpoint(engine, @opus_stereo_path)
      stereo_endpoint_id = "stereo_endpoint"

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, mono_endpoint, id: mono_endpoint_id)
      :ok = Engine.add_endpoint(engine, stereo_endpoint, id: stereo_endpoint_id)

      :ok =
        Agent.subscribe(engine, "agent", mono_endpoint_id, format: :pcm16, sample_rate: 16_000)

      :ok =
        Agent.subscribe(engine, @agent_id, stereo_endpoint_id,
          format: :pcm16,
          sample_rate: 24_000
        )

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: ^mono_endpoint_id,
                       track_id: mono_track_id,
                       track_metadata: nil
                     },
                     1000

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: ^stereo_endpoint_id,
                       track_id: stereo_track_id,
                       track_metadata: nil
                     },
                     1000

      assert_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          %TrackData{
                            peer_id: ^mono_endpoint_id,
                            track: %Notifications.Track{
                              id: ^mono_track_id,
                              type: :TRACK_TYPE_AUDIO,
                              metadata: "null"
                            },
                            data: data
                          }}
                     },
                     1000

      assert is_binary(data)
      assert byte_size(data) > 100

      assert_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          %TrackData{
                            peer_id: ^stereo_endpoint_id,
                            track: %Notifications.Track{
                              id: ^stereo_track_id,
                              type: :TRACK_TYPE_AUDIO,
                              metadata: "null"
                            },
                            data: data
                          }}
                     },
                     1000

      assert is_binary(data)
      assert byte_size(data) > 100
    end

    test "Agent ignores tracks of unsubscribed endpoints", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      mono_endpoint = create_file_endpoint(engine, @opus_mono_path)
      mono_endpoint_id = "mono_endpoint"

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, mono_endpoint, id: mono_endpoint_id)

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: ^mono_endpoint_id,
                       track_id: mono_track_id,
                       track_metadata: mono_metadata
                     },
                     1000

      refute_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          %TrackData{
                            peer_id: ^mono_endpoint_id,
                            track: %Notifications.Track{
                              id: ^mono_track_id,
                              type: :TRACK_TYPE_AUDIO,
                              metadata: ^mono_metadata
                            },
                            data: _data
                          }}
                     },
                     1000
    end

    test "Agent removes subscription when endpoint removed", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      mono_endpoint = create_file_endpoint(engine, @opus_mono_path)
      mono_endpoint_id = "mono_endpoint"

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, mono_endpoint, id: mono_endpoint_id)

      :ok =
        Agent.subscribe(engine, "agent", mono_endpoint_id,
          format: :pcm16,
          sample_rate: 16_000
        )

      assert_receive %Engine.Message.TrackAdded{
                       endpoint_id: ^mono_endpoint_id,
                       track_id: mono_track_id,
                       track_metadata: nil
                     },
                     1000

      assert_receive %Engine.Message.EndpointMessage{
                       endpoint_id: @agent_id,
                       endpoint_type: Agent,
                       message:
                         {:track_data,
                          %TrackData{
                            peer_id: ^mono_endpoint_id,
                            track: %Notifications.Track{
                              id: ^mono_track_id,
                              type: :TRACK_TYPE_AUDIO,
                              metadata: "null"
                            },
                            data: data
                          }}
                     },
                     1000

      assert is_binary(data)
      assert byte_size(data) > 100

      assert capture_log(fn ->
               :ok = Engine.remove_endpoint(engine, mono_endpoint_id)
               Process.sleep(1000)
             end) =~ "Removed subscription for endpoint \"#{mono_endpoint_id}\""

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

    test "Allows non-json metadata for track", %{rtc_engine: engine} do
      metadata = [
        {"", ""},
        {"meta", "meta"},
        {"{}", %{}},
        {Jason.encode!(%{name: "guy"}), %{"name" => "guy"}}
      ]

      agent_endpoint = create_agent_endpoint(engine)

      for {encoded, decoded} <- metadata do
        endpoint_id = UUID.uuid4()
        track_id = UUID.uuid4()
        :ok = Engine.add_endpoint(engine, agent_endpoint, id: endpoint_id)

        send_add_track_request(engine,
          agent_id: endpoint_id,
          metadata: encoded,
          track_id: track_id
        )

        assert_receive %Engine.Message.TrackAdded{
                         endpoint_id: ^endpoint_id,
                         track_id: ^track_id,
                         track_metadata: ^decoded,
                         track_type: :audio,
                         track_encoding: :opus
                       },
                       1000
      end

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

    test "Publishes opus 2-channel track", %{rtc_engine: engine} do
      # TODO: this test passes, although 2-channel opus is not supported yet
      agent_endpoint = create_agent_endpoint(engine)
      sink1 = create_sink_endpoint("sink1", engine)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, sink1, id: "sink1")

      start_opus_audio_pipeline(engine, @opus_stereo_path)

      assert_receive %Engine.Message.TrackAdded{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      assert count_sink_buffers("sink1") > 50

      assert_receive %Engine.Message.TrackRemoved{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      refute_receive %Engine.Message.EndpointCrashed{}, 1000
    end

    # FIXME: allow agent endpoint to handle multiple inputs
    @tag :skip
    test "Publishes two pcm16 tracks to other endpoints", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      sink1 = create_sink_endpoint("sink1", engine)
      sink2 = create_sink_endpoint("sink2", engine)

      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)
      :ok = Engine.add_endpoint(engine, sink1, id: "sink1")
      :ok = Engine.add_endpoint(engine, sink2, id: "sink2")

      start_raw_audio_pipeline(engine)
      start_raw_audio_pipeline(engine, track_id: @second_input_track_id)

      assert_receive %Engine.Message.TrackAdded{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      assert_receive %Engine.Message.TrackAdded{
        endpoint_id: @agent_id,
        track_id: @second_input_track_id
      }

      assert count_sink_buffers("sink1") > 50
      assert count_sink_buffers("sink2") > 50

      assert_receive %Engine.Message.TrackRemoved{
        endpoint_id: @agent_id,
        track_id: @input_track_id
      }

      assert_receive %Engine.Message.TrackRemoved{
        endpoint_id: @agent_id,
        track_id: @second_input_track_id
      }

      refute_receive %Engine.Message.EndpointCrashed{}, 1000
    end

    test "Invalid codec params", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)

      send_add_track_request(engine, sample_rate: 2137)

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

      send_add_track_request(engine, track_id: "defninitely-not-uuid")

      assert_receive %Engine.Message.EndpointCrashed{
                       endpoint_id: @agent_id,
                       reason: {%RuntimeError{message: message}, _stack}
                     },
                     1000

      assert message =~ "AddTrack request with invalid track_id"
    end

    test "Invalid track type", %{rtc_engine: engine} do
      agent_endpoint = create_agent_endpoint(engine)
      :ok = Engine.add_endpoint(engine, agent_endpoint, id: @agent_id)

      send_add_track_request(engine, track_type: :TRACK_TYPE_VIDEO)

      assert_receive %Engine.Message.EndpointCrashed{
                       endpoint_id: @agent_id,
                       reason: {%RuntimeError{message: message}, _stack}
                     },
                     1000

      assert message =~ "AddTrack request with invalid track type"
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
      250 -> count
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

  defp send_add_track_request(engine, opts) do
    add_track = %AddTrack{
      track: %Notifications.Track{
        id: Keyword.get(opts, :track_id, @input_track_id),
        type: Keyword.get(opts, :track_type, :TRACK_TYPE_AUDIO),
        metadata: Keyword.get(opts, :metadata, "{}")
      },
      codec_params: %CodecParameters{
        encoding: :TRACK_ENCODING_PCM16,
        sample_rate: Keyword.get(opts, :sample_rate, 24_000),
        channels: 1
      }
    }

    request = %AgentRequest{content: {:add_track, add_track}}

    agent_id = Keyword.get(opts, :agent_id, @agent_id)
    Engine.message_endpoint(engine, agent_id, {:agent_notification, request})
  end

  defp start_raw_audio_pipeline(engine, opts \\ []) do
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
          track_id: Keyword.get(opts, :track_id, @input_track_id)
        })
      ]
    )
  end

  defp start_opus_audio_pipeline(engine, opus_file \\ @opus_mono_path) do
    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:file_source, %Membrane.File.Source{location: opus_file})
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
