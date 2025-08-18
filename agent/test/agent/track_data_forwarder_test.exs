defmodule Membrane.RTC.Engine.Endpoint.Agent.TrackDataForwarderTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  require Membrane.Pad

  alias Membrane.Pad
  alias Membrane.Testing

  alias Membrane.Buffer

  alias Membrane.RTC.Engine.Endpoint.Agent.TrackDataForwarder

  @buffer_count 10

  setup do
    pipeline = start_pipeline()

    on_exit(fn -> Testing.Pipeline.terminate(pipeline) end)

    %{pipeline: pipeline}
  end

  test "parent sends track data messages", %{pipeline: pipeline} do
    track1_id = "my-first-track"
    payload1 = 1..@buffer_count |> Enum.to_list() |> Enum.map(&<<&1>>)

    track2_id = "my-second-track"
    payload2 = 1..@buffer_count |> Enum.to_list() |> Enum.map(&<<&1>>)

    add_track(pipeline, track1_id)
    add_track(pipeline, track2_id)

    Testing.Pipeline.execute_actions(pipeline,
      spec: [
        get_child(:forwarder)
        |> via_out(Pad.ref(:output, track1_id))
        |> child(:sink1, Testing.Sink),
        get_child(:forwarder)
        |> via_out(Pad.ref(:output, track2_id))
        |> child(:sink2, Testing.Sink)
      ]
    )

    for payload <- payload1 do
      send_data(pipeline, track1_id, payload)
    end

    assert received_buffers?(pipeline, :sink1)

    for payload <- payload2 do
      send_data(pipeline, track2_id, payload)
    end

    assert received_buffers?(pipeline, :sink2)
  end

  test "when add_track comes after linking", %{pipeline: pipeline} do
    track1_id = "my-first-track"
    payload1 = 1..@buffer_count |> Enum.to_list() |> Enum.map(&<<&1>>)

    Testing.Pipeline.execute_actions(pipeline,
      spec: [
        get_child(:forwarder)
        |> via_out(Pad.ref(:output, track1_id))
        |> child(:sink1, Testing.Sink)
      ]
    )

    Process.sleep(200)

    add_track(pipeline, track1_id)

    for payload <- payload1 do
      send_data(pipeline, track1_id, payload)
    end

    assert received_buffers?(pipeline, :sink1)
  end

  defp start_pipeline() do
    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:forwarder, TrackDataForwarder)
      ]
    )
  end

  defp received_buffers?(pipeline, sink_name) do
    assert_sink_buffer(pipeline, sink_name, %Buffer{payload: <<content>>})
    received_buffers?(pipeline, sink_name, content + 1)
  end

  defp received_buffers?(_pipeline, _sink_name, @buffer_count) do
    true
  end

  defp received_buffers?(pipeline, sink_name, next_element) do
    assert_sink_buffer(pipeline, sink_name, %Buffer{payload: <<^next_element>>})
    received_buffers?(pipeline, sink_name, next_element + 1)
  end

  defp send_data(pipeline, track_id, data) do
    Testing.Pipeline.notify_child(pipeline, :forwarder, {:track_data, track_id, data})
    Process.sleep(20)
  end

  defp add_track(pipeline, track_id) do
    codec_params = %{sample_rate: 24_000}
    Testing.Pipeline.notify_child(pipeline, :forwarder, {:new_track, track_id, codec_params})
  end
end
