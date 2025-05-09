defmodule Membrane.RTC.EngineTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.{Endpoint, Message, Track}
  alias Membrane.RTC.Engine.Message.{EndpointAdded, EndpointRemoved}

  alias Membrane.RTC.Engine.Support.{FakeSourceEndpoint, SinkEndpoint, TestEndpoint}

  @crash_endpoint_id "crash-endpoint"
  @track_endpoint_id "track-endpoint"

  setup do
    options = [
      module: Membrane.RTC.Engine
    ]

    pid = Membrane.Testing.Pipeline.start_link_supervised!(options)
    assert_pipeline_setup(pid, nil)

    Engine.register(pid, self())

    on_exit(fn -> assert :ok = Engine.terminate(pid) end)

    [rtc_engine: pid]
  end

  describe ":ready message" do
    test "triggers :new_endpoint", %{rtc_engine: rtc_engine} do
      endpoint_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self()}
      first_endpoint = "endpoint1"
      second_endpoint = "endpoint2"

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: first_endpoint)
      # make first endpoint ready so it can receive notification about new endpoints
      Engine.message_endpoint(
        rtc_engine,
        first_endpoint,
        {:execute_actions, [notify_parent: {:ready, nil}]}
      )

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: second_endpoint)

      Engine.message_endpoint(
        rtc_engine,
        second_endpoint,
        {:execute_actions, [notify_parent: {:ready, "metadata"}]}
      )

      assert_receive %EndpointAdded{endpoint_id: ^first_endpoint}
      assert_receive %EndpointAdded{endpoint_id: ^second_endpoint}
      assert_receive {:new_endpoint, %Endpoint{id: ^second_endpoint, metadata: "metadata"}}
      assert_receive {:ready, [%Endpoint{id: "endpoint1", metadata: nil, type: TestEndpoint}]}
      refute_receive {:new_tracks, []}
    end

    test "reports other endpoints", %{rtc_engine: rtc_engine} do
      endpoint1_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self()}
      endpoint1_track = video_track("endpoint1", "track1", "track1-metadata", "stream1")
      endpoint2_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self()}

      Engine.add_endpoint(rtc_engine, endpoint1_spec, id: "endpoint1")

      Engine.message_endpoint(
        rtc_engine,
        "endpoint1",
        {:execute_actions,
         [
           notify_parent: {:ready, "endpoint1-metadata"},
           notify_parent: {:publish, {:new_tracks, [endpoint1_track]}}
         ]}
      )

      assert_receive {:ready,
                      [
                        %Endpoint{
                          id: "endpoint1",
                          metadata: "endpoint1-metadata",
                          type: TestEndpoint
                        }
                      ]}

      Engine.add_endpoint(rtc_engine, endpoint2_spec, id: "endpoint2")

      Engine.message_endpoint(
        rtc_engine,
        "endpoint2",
        {:execute_actions, [notify_parent: {:ready, "endpoint2-metadata"}]}
      )

      assert_receive {:ready, endpoints_in_room}

      assert [
               %Endpoint{
                 id: "endpoint2",
                 metadata: "endpoint2-metadata",
                 type: TestEndpoint
               },
               %Endpoint{
                 id: "endpoint1",
                 metadata: "endpoint1-metadata",
                 type: TestEndpoint,
                 inbound_tracks: %{
                   "track1" => %Track{
                     id: "track1",
                     origin: "endpoint1",
                     metadata: "track1-metadata"
                   }
                 }
               }
             ] = endpoints_in_room

      assert_receive {:new_tracks, [%Track{id: "track1"}]}
    end

    test "doesn't crash if sent in wrong order", %{rtc_engine: rtc_engine} do
      endpoint_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self()}
      first_endpoint = "endpoint1"
      second_endpoint = "endpoint2"

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: first_endpoint)

      endpoint1_track = video_track("endpoint1", "track1", "track1-metadata", "stream1")

      Engine.message_endpoint(
        rtc_engine,
        "endpoint1",
        {:execute_actions, [notify_parent: {:publish, {:new_tracks, [endpoint1_track]}}]}
      )

      refute_receive {:ready,
                      [
                        %Endpoint{
                          id: "endpoint1",
                          metadata: "endpoint1-metadata",
                          type: TestEndpoint
                        }
                      ]}

      refute_receive {:new_tracks, []}

      Engine.message_endpoint(
        rtc_engine,
        "endpoint1",
        {:execute_actions,
         [
           notify_parent: {:ready, "endpoint1-metadata"},
           notify_parent: {:publish, {:new_tracks, [endpoint1_track]}}
         ]}
      )

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: second_endpoint)

      Engine.message_endpoint(
        rtc_engine,
        "endpoint2",
        {:execute_actions, [notify_parent: {:ready, "endpoint2-metadata"}]}
      )

      assert_receive {:ready,
                      [
                        %Endpoint{
                          id: "endpoint1",
                          metadata: "endpoint1-metadata",
                          type: TestEndpoint
                        }
                      ]}

      assert_receive {:ready,
                      [
                        %Endpoint{
                          id: "endpoint2",
                          metadata: "endpoint2-metadata",
                          type: TestEndpoint
                        },
                        %Endpoint{
                          id: "endpoint1",
                          metadata: "endpoint1-metadata",
                          type: TestEndpoint
                        }
                      ]}

      assert_receive {:new_tracks, [%Track{id: "track1"}]}
    end
  end

  describe ":Engine.add/remove_endpoint" do
    test "adds endpoint when old one is in terminating state", %{rtc_engine: rtc_engine} do
      endpoint_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self(), delay_termination: 500}

      endpoint_id = "endpoint"

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)

      assert_receive %EndpointAdded{}

      Engine.remove_endpoint(rtc_engine, endpoint_id)
      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)
      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)

      assert_receive %EndpointRemoved{}
      refute_receive %EndpointAdded{}
      assert_receive %EndpointAdded{}, 600

      Engine.remove_endpoint(rtc_engine, endpoint_id)

      assert_receive %EndpointRemoved{}
      refute_receive %EndpointAdded{}, 600
    end

    test "removes pending addition of endpoint when remove_endpoint is called", %{
      rtc_engine: rtc_engine
    } do
      endpoint_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self(), delay_termination: 500}
      endpoint_id = "endpoint"

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)

      assert_receive %EndpointAdded{}

      Engine.remove_endpoint(rtc_engine, endpoint_id)
      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)
      Engine.remove_endpoint(rtc_engine, endpoint_id)

      assert_receive %EndpointRemoved{}
      assert_receive %EndpointAdded{}
      assert_receive %EndpointRemoved{}
    end

    test "add the same endpoint multiple times", %{rtc_engine: rtc_engine} do
      endpoint_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self(), delay_termination: 500}
      endpoint_id = "endpoint"

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)
      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)
      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)

      Engine.remove_endpoint(rtc_engine, endpoint_id)

      assert_receive %EndpointAdded{}
      refute_receive %EndpointAdded{}
      assert_receive %EndpointRemoved{}
      refute_receive %EndpointRemoved{}
    end

    test "remove the same endpoint multiple times", %{rtc_engine: rtc_engine} do
      endpoint_spec = %TestEndpoint{rtc_engine: rtc_engine, owner: self(), delay_termination: 500}
      endpoint_id = "endpoint"

      Engine.add_endpoint(rtc_engine, endpoint_spec, id: endpoint_id)

      Engine.remove_endpoint(rtc_engine, endpoint_id)
      Engine.remove_endpoint(rtc_engine, endpoint_id)
      Engine.remove_endpoint(rtc_engine, endpoint_id)

      assert_receive %EndpointAdded{}
      assert_receive %EndpointRemoved{}
      refute_receive %EndpointRemoved{}
    end
  end

  describe ":track_encoding_enabled/disabled" do
    setup :setup_for_metadata_tests

    test "second endpoint receives proper notifications", %{
      rtc_engine: rtc_engine,
      track: %Track{id: track_id},
      endpoint: %{id: endpoint_id}
    } do
      :ok = Engine.add_endpoint(rtc_engine, %SinkEndpoint{owner: self(), rtc_engine: rtc_engine})

      assert_receive %EndpointAdded{}

      Engine.message_endpoint(
        rtc_engine,
        endpoint_id,
        {:execute_actions, [notify_parent: {:disable_track_variant, track_id, :high}]}
      )

      assert_receive {:track_variant_disabled, %Track{id: ^track_id}, :high}

      [%Track{id: ^track_id, disabled_variants: disabled_variants} | _rest] =
        Engine.get_tracks(rtc_engine)

      assert [:high] = disabled_variants

      Engine.message_endpoint(
        rtc_engine,
        endpoint_id,
        {:execute_actions, [notify_parent: {:enable_track_variant, track_id, :high}]}
      )

      assert_receive {:track_variant_enabled, %Track{id: ^track_id}, :high}
    end
  end

  describe ":update_track_metadata" do
    setup :setup_for_metadata_tests

    test "triggers :track_metadata_updated", %{
      rtc_engine: rtc_engine,
      track: %Track{id: track_id},
      endpoint: %{id: endpoint_id}
    } do
      Engine.message_endpoint(
        rtc_engine,
        endpoint_id,
        {:execute_actions, [notify_parent: {:update_track_metadata, track_id, "new-metadata"}]}
      )

      assert_receive {:track_metadata_updated, %Track{id: ^track_id, metadata: "new-metadata"}}
    end

    test "ignores identical metadata", %{
      rtc_engine: rtc_engine,
      track: track,
      endpoint: %{id: endpoint_id}
    } do
      Engine.message_endpoint(
        rtc_engine,
        endpoint_id,
        {:execute_actions, [notify_parent: {:update_track_metadata, track.id, track.metadata}]}
      )

      refute_receive {:track_metadata_updated, _track}
    end

    @tag no_subscribe: true
    test "return updated track upon subscription", %{
      rtc_engine: rtc_engine,
      track: %Track{id: track_id} = track,
      endpoint: %{id: endpoint_id},
      server_endpoint_id: server_endpoint_id
    } do
      new_metadata = "new-metadata"

      Engine.message_endpoint(
        rtc_engine,
        endpoint_id,
        {:execute_actions, [notify_parent: {:update_track_metadata, track_id, new_metadata}]}
      )

      refute_receive {:track_metadata_updated, _track}

      assert {:ok, %Track{} = updated_track} =
               Engine.subscribe(rtc_engine, server_endpoint_id, track_id)

      track = %{track | metadata: new_metadata}
      assert track == updated_track
    end
  end

  describe ":update_endpoint_metadata" do
    setup :setup_for_metadata_tests

    test "triggers :endpoint_metadata_updated", %{
      rtc_engine: rtc_engine,
      endpoint: %{id: endpoint_id}
    } do
      Engine.message_endpoint(
        rtc_engine,
        endpoint_id,
        {:execute_actions, [notify_parent: {:update_endpoint_metadata, "new-metadata"}]}
      )

      assert_receive {:endpoint_metadata_updated,
                      %Endpoint{id: ^endpoint_id, metadata: "new-metadata"}}
    end

    test "ignores identical metadata", %{rtc_engine: rtc_engine, endpoint: endpoint} do
      Engine.message_endpoint(
        rtc_engine,
        endpoint.id,
        {:execute_actions, [notify_parent: {:update_endpoint_metadata, endpoint.metadata}]}
      )

      refute_receive {:endpoint_metadata_updated, _track}
    end
  end

  describe "Engine.message_endpoint/3" do
    test "forwards message to endpoint", %{rtc_engine: rtc_engine} do
      endpoint = %TestEndpoint{rtc_engine: rtc_engine, owner: self()}
      endpoint_id = :test_endpoint
      :ok = Engine.add_endpoint(rtc_engine, endpoint, id: endpoint_id)
      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, :message)
      assert_receive(:message, 1_000)
    end

    test "does nothing when endpoint doesn't exist", %{rtc_engine: rtc_engine} do
      endpoint_id = :test_endpoint
      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, :message)
      refute_receive :message
    end
  end

  describe "Engine.get_endpoints/2" do
    test "get list of endpoints", %{rtc_engine: rtc_engine} do
      endpoint = %TestEndpoint{rtc_engine: rtc_engine, owner: self()}
      endpoint_id = :test_endpoint
      :ok = Engine.add_endpoint(rtc_engine, endpoint, id: endpoint_id)
      endpoints = Engine.get_endpoints(rtc_engine)
      assert [%{id: ^endpoint_id, type: TestEndpoint}] = endpoints
    end
  end

  describe "Engine.get_forwarded_tracks/2" do
    test "get forwarded tracks", %{rtc_engine: rtc_engine} do
      video_endpoint_id = :video1
      video_endpoint = create_video_file_endpoint(rtc_engine, video_endpoint_id, "1", "1")
      :ok = Engine.add_endpoint(rtc_engine, video_endpoint, id: video_endpoint_id)

      assert 0 = Engine.get_num_forwarded_tracks(rtc_engine)

      endpoint_id1 = :fake_endpoint1

      :ok =
        Engine.add_endpoint(rtc_engine, %SinkEndpoint{rtc_engine: rtc_engine, owner: self()},
          id: endpoint_id1
        )

      Engine.message_endpoint(rtc_engine, video_endpoint_id, :start)

      assert_receive ^endpoint_id1, 1_000

      assert 1 = Engine.get_num_forwarded_tracks(rtc_engine)

      endpoint_id2 = :fake_endpoint2

      :ok =
        Engine.add_endpoint(rtc_engine, %SinkEndpoint{rtc_engine: rtc_engine, owner: self()},
          id: endpoint_id2
        )

      assert_receive ^endpoint_id2, 1_000

      assert 2 = Engine.get_num_forwarded_tracks(rtc_engine)

      endpoint_id3 = :fake_endpoint3

      :ok =
        Engine.add_endpoint(rtc_engine, %SinkEndpoint{rtc_engine: rtc_engine, owner: self()},
          id: endpoint_id3
        )

      assert_receive ^endpoint_id3, 1_000

      assert 3 = Engine.get_num_forwarded_tracks(rtc_engine)

      add_video_file_endpoint(rtc_engine, :video2, "2", "2")

      assert_receive ^endpoint_id1, 10_000
      assert_receive ^endpoint_id2, 10_000
      assert_receive ^endpoint_id3, 10_000

      assert 6 = Engine.get_num_forwarded_tracks(rtc_engine)

      add_video_file_endpoint(rtc_engine, :video3, "3", "3")

      assert_receive ^endpoint_id1, 10_000
      assert_receive ^endpoint_id2, 10_000
      assert_receive ^endpoint_id3, 10_000

      assert 9 = Engine.get_num_forwarded_tracks(rtc_engine)
    end
  end

  describe "engine sends messages" do
    test "Endpoint{Added, MetadataUpdated, Crashed, Removed}, Track{Added, Removed, MetadataUpdated}",
         %{
           rtc_engine: rtc_engine
         } do
      endpoint = %TestEndpoint{rtc_engine: rtc_engine}
      endpoint_id = :test_endpoint

      :ok = Engine.add_endpoint(rtc_engine, endpoint, id: endpoint_id)

      assert_receive %EndpointAdded{
        endpoint_id: ^endpoint_id,
        endpoint_type: TestEndpoint
      }

      endpoint_metadata = "metadata 101"
      msg = {:execute_actions, notify_parent: {:ready, endpoint_metadata}}

      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, msg)

      assert_receive %Message.EndpointMetadataUpdated{
        endpoint_id: ^endpoint_id,
        endpoint_metadata: ^endpoint_metadata
      }

      track_id = "track1"
      track_metadata = "video_track_meta"
      track = video_track(endpoint_id, track_id, track_metadata)
      track_encoding = track.encoding

      msg = {:execute_actions, notify_parent: {:publish, {:new_tracks, [track]}}}

      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, msg)

      assert_receive %Message.TrackAdded{
        endpoint_id: ^endpoint_id,
        endpoint_type: TestEndpoint,
        track_id: ^track_id,
        track_type: :video,
        track_encoding: ^track_encoding,
        track_metadata: ^track_metadata
      }

      endpoint_metadata_2 = "metadata 404"

      msg = {:execute_actions, notify_parent: {:update_endpoint_metadata, endpoint_metadata_2}}

      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, msg)

      assert_receive %Message.EndpointMetadataUpdated{
        endpoint_id: ^endpoint_id,
        endpoint_metadata: ^endpoint_metadata_2
      }

      track_metadata = "{\"name\": \"hello\"}"
      msg = {:execute_actions, notify_parent: {:update_track_metadata, track_id, track_metadata}}
      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, msg)

      assert_receive %Message.TrackMetadataUpdated{
        endpoint_id: ^endpoint_id,
        track_id: ^track_id,
        track_metadata: ^track_metadata
      }

      msg = {:execute_actions, notify_parent: {:publish, {:removed_tracks, [track]}}}
      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, msg)

      assert_receive %Message.TrackRemoved{
        endpoint_id: ^endpoint_id,
        endpoint_type: TestEndpoint,
        track_id: ^track_id,
        track_type: :video,
        track_encoding: ^track_encoding
      }

      msg = {:execute_actions, notify_parent: {:forward_to_parent, :test_message}}
      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, msg)

      assert_receive %Message.EndpointMessage{
        endpoint_id: ^endpoint_id,
        endpoint_type: TestEndpoint,
        message: :test_message
      }

      :ok = Engine.remove_endpoint(rtc_engine, endpoint_id)

      assert_receive %EndpointRemoved{
        endpoint_id: ^endpoint_id,
        endpoint_type: TestEndpoint
      }

      endpoint_id = :test_endpoint2
      :ok = Engine.add_endpoint(rtc_engine, endpoint, id: endpoint_id)

      assert_receive %EndpointAdded{
        endpoint_id: ^endpoint_id,
        endpoint_type: TestEndpoint
      }

      msg = {:execute_actions, [:some_invalid_action]}
      :ok = Engine.message_endpoint(rtc_engine, endpoint_id, msg)

      assert_receive %Message.EndpointCrashed{
        endpoint_id: ^endpoint_id,
        endpoint_type: TestEndpoint,
        reason: {%Membrane.ActionError{message: message}, _stack}
      }

      assert String.contains?(message, "Error while handling action :some_invalid_action")
    end
  end

  describe "engine crash group handling" do
    setup :setup_for_crash_tests

    test "does not return endpoint that is currently crashing", %{rtc_engine: rtc_engine} do
      add_slow_endpoint(rtc_engine, @crash_endpoint_id)
      msg = {:execute_actions, [:some_invalid_action]}
      :ok = Engine.message_endpoint(rtc_engine, @crash_endpoint_id, msg)

      assert_child_terminated(rtc_engine, {:endpoint, @crash_endpoint_id}, nil)

      assert Engine.get_endpoints(rtc_engine) |> Enum.map(& &1.id) == [@track_endpoint_id]

      refute_pipeline_crash_group_down(rtc_engine, {@crash_endpoint_id, TestEndpoint}, nil)

      assert_pipeline_crash_group_down(rtc_engine, {@crash_endpoint_id, TestEndpoint}, 600)

      assert_receive %Message.EndpointCrashed{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint,
        reason: {%Membrane.ActionError{message: message}, _stack}
      }

      assert String.contains?(message, "Error while handling action :some_invalid_action")
    end

    test "does not send messages to crashing group", %{rtc_engine: rtc_engine, track: track} do
      add_slow_endpoint(rtc_engine, @crash_endpoint_id)
      msg = {:execute_actions, [:some_invalid_action]}
      :ok = Engine.message_endpoint(rtc_engine, @crash_endpoint_id, msg)

      assert_child_terminated(rtc_engine, {:endpoint, @crash_endpoint_id}, nil)

      msg =
        {:execute_actions,
         notify_parent:
           {:publish,
            %Engine.Notifications.TrackNotification{
              track_id: track.id,
              notification: {"subscriber", "check"}
            }}}

      Engine.message_endpoint(rtc_engine, @track_endpoint_id, msg)

      refute_pipeline_crash_group_down(rtc_engine, {@crash_endpoint_id, TestEndpoint}, nil)
      assert_pipeline_crash_group_down(rtc_engine, {@crash_endpoint_id, TestEndpoint}, 600)

      assert_receive %Message.EndpointCrashed{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint,
        reason: {%Membrane.ActionError{message: message}, _stack}
      }

      assert String.contains?(message, "Error while handling action :some_invalid_action")
    end

    test "does dispatch message when crash happens during termination", %{rtc_engine: rtc_engine} do
      add_crashing_terminate_endpoint(rtc_engine, @crash_endpoint_id)

      :ok = Engine.remove_endpoint(rtc_engine, @crash_endpoint_id)

      Membrane.Testing.Pipeline.execute_actions(
        rtc_engine,
        remove_children: {:terminatecrash, @crash_endpoint_id}
      )

      assert_receive %Message.EndpointRemoved{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint
      }

      assert_pipeline_crash_group_down(rtc_engine, {@crash_endpoint_id, TestEndpoint}, nil)

      assert_receive %Message.EndpointCrashed{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint,
        reason: {:error, "Triggered crash in terminate request"}
      }
    end

    test "creates new endpoint if there was a pending addition", %{
      rtc_engine: rtc_engine
    } do
      add_crashing_terminate_endpoint(rtc_engine, @crash_endpoint_id)

      assert_receive %Message.EndpointAdded{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint
      }

      :ok =
        Engine.message_endpoint(
          rtc_engine,
          @crash_endpoint_id,
          {:update_state, %{delay_termination: 500}}
        )

      :ok = Engine.remove_endpoint(rtc_engine, @crash_endpoint_id)

      :ok =
        Engine.add_endpoint(rtc_engine, %TestEndpoint{rtc_engine: rtc_engine},
          id: @crash_endpoint_id
        )

      refute_child_terminated(rtc_engine, {:endpoint, @crash_endpoint_id}, nil)

      assert_receive %Message.EndpointRemoved{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint
      }

      refute_receive %Message.EndpointAdded{endpoint_id: @crash_endpoint_id}

      Membrane.Testing.Pipeline.execute_actions(
        rtc_engine,
        remove_children: {:terminatecrash, @crash_endpoint_id}
      )

      assert_pipeline_crash_group_down(rtc_engine, {@crash_endpoint_id, TestEndpoint}, 600)

      assert_receive %Message.EndpointCrashed{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint,
        reason: {:error, "Triggered crash in terminate request"}
      }

      assert_receive %Message.EndpointAdded{
        endpoint_id: @crash_endpoint_id,
        endpoint_type: TestEndpoint
      }
    end
  end

  defp video_track(endpoint_id, track_id, metadata, stream_id \\ "test-stream") do
    Engine.Track.new(:video, stream_id, endpoint_id, :VP8, nil, nil,
      id: track_id,
      metadata: metadata
    )
  end

  defp setup_for_metadata_tests(%{rtc_engine: rtc_engine} = ctx) do
    track = video_track(@track_endpoint_id, "track1", "track-metadata")

    endpoint = %Endpoint{
      id: @track_endpoint_id,
      type: Endpoint.WebRTC,
      metadata: "original-metadata"
    }

    track_endpoint = %TestEndpoint{rtc_engine: rtc_engine}

    server_endpoint = %TestEndpoint{
      rtc_engine: rtc_engine,
      owner: self()
    }

    Engine.add_endpoint(rtc_engine, track_endpoint, id: endpoint.id)

    Engine.message_endpoint(
      rtc_engine,
      endpoint.id,
      {:execute_actions,
       notify_parent: {:ready, endpoint.metadata},
       notify_parent: {:publish, {:new_tracks, [track]}}}
    )

    server_endpoint_id = "server-endpoint"

    Engine.add_endpoint(rtc_engine, server_endpoint, id: server_endpoint_id)

    Engine.message_endpoint(
      rtc_engine,
      server_endpoint_id,
      {:execute_actions, [notify_parent: {:ready, nil}]}
    )

    assert_receive {:new_tracks, [%Track{id: "track1"}]}

    if Map.get(ctx, :no_subscribe) == nil do
      assert {:ok, ^track} = Engine.subscribe(rtc_engine, server_endpoint_id, "track1")
    end

    Engine.message_endpoint(
      rtc_engine,
      endpoint.id,
      {:execute_actions,
       [notify_parent: {:track_ready, track.id, hd(track.variants), track.encoding}]}
    )

    [
      track: track,
      track_endpoint: track_endpoint,
      server_endpoint_id: server_endpoint_id,
      endpoint: endpoint
    ]
  end

  defp add_slow_endpoint(rtc_engine, endpoint_id) do
    add_endpoint_to_group(rtc_engine, endpoint_id, :longcrash, delay_termination: 500)
  end

  defp add_crashing_terminate_endpoint(rtc_engine, endpoint_id) do
    add_endpoint_to_group(rtc_engine, endpoint_id, :terminatecrash, crash_while_terminating: true)
  end

  defp add_endpoint_to_group(rtc_engine, endpoint_id, name, opts) do
    opts = [rtc_engine: rtc_engine] ++ opts

    spec = {
      child({name, endpoint_id}, struct(TestEndpoint, opts)),
      group: {endpoint_id, TestEndpoint}, crash_group_mode: :temporary
    }

    Membrane.Testing.Pipeline.execute_actions(rtc_engine, spec: spec)
  end

  defp setup_for_crash_tests(%{rtc_engine: rtc_engine}) do
    track_id = "traczek"

    crash_endpoint = %TestEndpoint{rtc_engine: rtc_engine}
    track_endpoint = %TestEndpoint{rtc_engine: rtc_engine}
    track = video_track(@track_endpoint_id, track_id, nil)

    Engine.add_endpoint(rtc_engine, track_endpoint, id: @track_endpoint_id)
    Engine.add_endpoint(rtc_engine, crash_endpoint, id: @crash_endpoint_id)

    Engine.message_endpoint(
      rtc_engine,
      @track_endpoint_id,
      {:execute_actions,
       notify_parent: {:ready, @track_endpoint_id},
       notify_parent: {:publish, {:new_tracks, [track]}},
       notify_parent: {:track_ready, track.id, :high, track.encoding}}
    )

    Engine.message_endpoint(
      rtc_engine,
      @crash_endpoint_id,
      {:execute_actions, notify_parent: {:ready, @crash_endpoint_id}}
    )

    assert_pipeline_notified(
      rtc_engine,
      {:endpoint, @track_endpoint_id},
      {:publish, {:new_tracks, [^track]}},
      nil
    )

    {:ok, _track} = Engine.subscribe(rtc_engine, @crash_endpoint_id, track.id, [])

    [
      crash_endpoint: crash_endpoint,
      track_endpoint: track_endpoint,
      track: track
    ]
  end

  defp add_video_file_endpoint(
         rtc_engine,
         video_endpoint_id,
         stream_id,
         video_track_id
       ) do
    video_endpoint =
      create_video_file_endpoint(rtc_engine, video_endpoint_id, stream_id, video_track_id)

    :ok = Engine.add_endpoint(rtc_engine, video_endpoint, id: video_endpoint_id)

    assert_receive %EndpointAdded{endpoint_id: ^video_endpoint_id}

    Engine.message_endpoint(rtc_engine, video_endpoint_id, :start)

    assert_receive %Message.TrackAdded{
                     endpoint_id: ^video_endpoint_id,
                     track_id: ^video_track_id
                   },
                   2_500
  end

  defp create_video_file_endpoint(
         rtc_engine,
         video_file_endpoint_id,
         stream_id,
         video_track_id
       ) do
    video_track =
      Engine.Track.new(
        :video,
        stream_id,
        video_file_endpoint_id,
        :H264,
        90_000,
        %ExSDP.Attribute.FMTP{
          pt: 96
        },
        id: video_track_id
      )

    %FakeSourceEndpoint{
      rtc_engine: rtc_engine,
      track: video_track
    }
  end
end
