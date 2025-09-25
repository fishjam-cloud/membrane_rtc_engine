defmodule Membrane.RTC.Engine.Endpoint.Agent.AudioBufferTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing
  alias Membrane.Time

  alias Membrane.RTC.Engine.Endpoint.Agent.{AudioBuffer, Timestamper}

  @buffer_duration Time.milliseconds(10)
  @fake_buffer_duration Time.milliseconds(50)
  @audio_buffer_queue_length trunc(Time.seconds(10) / @fake_buffer_duration)

  test "sends all buffers" do
    payload = [1, 2, 3, 4] |> Enum.map(&<<&1>>)

    pipeline = start_pipeline(payload)

    for data <- payload do
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^data})
    end
  end

  test "sends all buffers - with realtimer" do
    payload = 1..15 |> Enum.to_list() |> Enum.map(&<<&1>>)

    pipeline = start_pipeline(payload, realtimer?: true)

    for data <- payload do
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^data})
    end
  end

  test "sends eos after buffers" do
    # Membrane Core automatically makes initial demand for 100 buffers
    # In this test we check if after the initial 100 buffers demanded,
    # The sink doesn't immediately receive the end_of_stream
    # The EOS should be received after the last 10 buffers
    payload = 1..110 |> Enum.map(&<<&1>>)

    pipeline = start_pipeline(payload, sink: %Testing.Sink{autodemand: false})

    refute_sink_buffer(pipeline, :sink, _buffer)
    refute_child_terminated(pipeline, :sink)

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 100})

    refute_sink_event(pipeline, :sink, :end_of_stream)

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 110})

    assert_end_of_stream(pipeline, :sink)
  end

  test "drops buffers if over the limit" do
    payload = 1..(2 * @audio_buffer_queue_length) |> Enum.map(&<<&1>>)

    pipeline = start_pipeline(payload, realtimer?: true)

    for data <- Enum.take(payload, @audio_buffer_queue_length) do
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^data})
    end

    count = count_sink_buffers(pipeline)
    assert count < @audio_buffer_queue_length
  end

  test "doesn't drop buffers if max duration increased" do
    payload = 1..(2 * @audio_buffer_queue_length) |> Enum.map(&<<&1>>)

    pipeline =
      start_pipeline(payload,
        sink: %Testing.Sink{autodemand: false},
        max_buffered_duration: 2 * @audio_buffer_queue_length * @fake_buffer_duration
      )

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 2 * @audio_buffer_queue_length})

    for data <- payload do
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^data})
    end

    assert_end_of_stream(pipeline, :sink)
  end

  test "clear event prevents queued buffers from being sent" do
    payload = 1..50 |> Enum.map(&<<&1>>)

    # Membrane Core preemptively makes demands up to sink_queue_size
    # We set it to 30 to prevent preemptively making too many demands
    pipeline =
      start_pipeline(payload, sink: %Testing.Sink{autodemand: false}, sink_queue_size: 30)

    refute_sink_buffer(pipeline, :sink, _any)

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 30})
    Testing.Pipeline.notify_child(pipeline, :timestamper, :interrupt_track)

    for data <- payload |> Enum.take(30) do
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: ^data})
    end

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 20})

    refute_sink_buffer(pipeline, :sink, _any)

    assert_end_of_stream(pipeline, :sink)
  end

  defp count_sink_buffers(pipeline, count \\ 0) do
    receive do
      {Testing.Pipeline, ^pipeline, {:handle_child_notification, {{:buffer, _any}, :sink}}} ->
        count_sink_buffers(count + 1)
    after
      200 -> count
    end
  end

  defp start_pipeline(payload, opts \\ []) do
    source = %Testing.Source{
      output: {%{last_pts: 0, buffers: payload}, &test_source_handle_demand/2},
      stream_format: %Membrane.RawAudio{channels: 1, sample_rate: 16_000, sample_format: :s16le}
    }

    audio_buffer =
      case Keyword.fetch(opts, :max_buffered_duration) do
        {:ok, duration} -> %AudioBuffer{max_buffered_duration: duration}
        :error -> AudioBuffer
      end

    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:source, source)
        |> child(:timestamper, Timestamper)
        |> child(:buffer, audio_buffer)
        |> extra_elements(opts)
        |> via_in(:input, target_queue_size: Keyword.get(opts, :sink_queue_size))
        |> child(
          :sink,
          Keyword.get(opts, :sink, %Membrane.Testing.Sink{})
        )
      ]
    )
  end

  defp extra_elements(link, realtimer?: true) do
    child(link, :realtimer, Membrane.Realtimer)
  end

  defp extra_elements(link, _opts) do
    link
  end

  defp test_source_handle_demand(state, size) do
    num_buffers = min(length(state.buffers), size)

    if num_buffers == 0 do
      {[], state}
    else
      buffers =
        state.buffers
        |> Enum.take(num_buffers)
        |> Enum.with_index(&{&2 + 1, &1})
        |> Enum.map(fn {idx, payload} ->
          {:buffer,
           {:output,
            %Membrane.Buffer{
              payload: payload,
              pts: state.last_pts + idx * @buffer_duration,
              metadata: %{duration: @fake_buffer_duration}
            }}}
        end)

      state = %{
        state
        | buffers: Enum.drop(state.buffers, num_buffers),
          last_pts: state.last_pts + num_buffers * @buffer_duration
      }

      maybe_eos =
        if Enum.empty?(state.buffers), do: [end_of_stream: :output], else: []

      {buffers ++ maybe_eos, state}
    end
  end
end
