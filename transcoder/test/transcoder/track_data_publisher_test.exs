defmodule Membrane.RTC.Engine.Endpoint.Transcoder.TrackDataPublisherTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  require Membrane.Pad

  alias Membrane.Pad
  alias Membrane.Testing

  alias Membrane.RTC.Engine.Endpoint.Transcoder.TrackDataPublisher

  setup do
    pipeline = start_pipeline()

    on_exit(fn -> Testing.Pipeline.terminate(pipeline) end)

    %{pipeline: pipeline}
  end

  test "parent receives notifications", %{pipeline: pipeline} do
    pad1 = Pad.ref(:input, :track1)
    payload1 = [1, 2, 3, 4]
    source1 = %Testing.Source{output: payload1}

    pad2 = Pad.ref(:input, :track2)
    payload2 = [11, 12, 13, 14]
    source2 = %Testing.Source{output: payload2}

    Testing.Pipeline.execute_actions(pipeline,
      spec: [
        child(:source1, source1) |> via_in(pad1) |> get_child(:publisher),
        child(:source2, source2) |> via_in(pad2) |> get_child(:publisher)
      ]
    )

    for payload <- payload1 do
      assert_receive_track_data(pipeline, :track1, payload)
    end

    for payload <- payload2 do
      assert_receive_track_data(pipeline, :track2, payload)
    end
  end

  defp start_pipeline() do
    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:publisher, TrackDataPublisher)
      ]
    )
  end

  defp assert_receive_track_data(pipeline, track_id, payload) do
    assert_pipeline_notified(
      pipeline,
      :publisher,
      {:track_data, ^track_id, %Membrane.Buffer{payload: ^payload}}
    )
  end
end
