defmodule Membrane.RTC.Engine.Endpoint.Agent.AudioBufferTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing
  alias Membrane.Time

  alias Membrane.RTC.Engine.Endpoint.Agent.AudioBuffer

  @buffer_duration Time.milliseconds(10)
  @fake_buffer_duration Time.milliseconds(50)
  @audio_buffer_queue_length trunc(Time.seconds(10) / @fake_buffer_duration)

  test "sends all buffers" do
    payload = [1, 2, 3, 4] |> Enum.map(&<<&1>>)

    start_pipeline(payload)

    for data <- payload do
      assert_receive_buffer(data)
    end
  end

  test "sends all buffers - with realtimer" do
    payload = 1..15 |> Enum.to_list() |> Enum.map(&<<&1>>)

    start_pipeline(payload, realtimer?: true)

    for data <- payload do
      assert_receive_buffer(data)
    end
  end

  test "sends eos after buffers" do
    # Membrane Core automatically makes initial demand for 100 buffers
    # In this test we check if after the initial 100 buffers demanded,
    # The sink doesn't immediately receive the end_of_stream
    # The EOS should be received after the last 10 buffers
    payload = 1..110 |> Enum.to_list() |> Enum.map(&<<&1>>)

    pipeline = start_pipeline(payload, sink: %Testing.Sink{autodemand: false})

    refute_sink_buffer(pipeline, :sink, _buffer)
    refute_child_terminated(pipeline, :sink)

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 100})

    refute_receive {Testing.Pipeline, ^pipeline,
                    {:handle_element_end_of_stream, {:sink, :input}}},
                   2000

    Testing.Pipeline.notify_child(pipeline, :sink, {:make_demand, 110})

    assert_end_of_stream(pipeline, :sink)
  end

  test "drops buffers if over the limit" do
    payload = 1..(2 * @audio_buffer_queue_length) |> Enum.map(&<<&1>>)

    start_pipeline(payload, realtimer?: true)

    for data <- Enum.take(payload, @audio_buffer_queue_length) do
      assert_receive_buffer(data)
    end

    count = count_sink_buffers()
    assert count < @audio_buffer_queue_length
  end

  defp assert_receive_buffer(data) do
    assert_receive {:sink_buffer, %Buffer{payload: ^data}}, 250
  end

  defp count_sink_buffers(count \\ 0) do
    receive do
      {:sink_buffer, %Buffer{}} -> count_sink_buffers(count + 1)
    after
      200 -> count
    end
  end

  defp start_pipeline(payload, opts \\ []) do
    test_process_pid = self()

    source = %Testing.Source{
      output: {%{last_pts: 0, buffers: payload}, &test_source_handle_demand/2},
      stream_format: %Membrane.RawAudio{channels: 1, sample_rate: 16_000, sample_format: :s16le}
    }

    realtimer =
      if Keyword.get(opts, :realtimer?, false) do
        fn link -> child(link, :realtimer, Membrane.Realtimer) end
      else
        & &1
      end

    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:source, source)
        |> child(:buffer, AudioBuffer)
        |> realtimer.()
        |> child(
          :sink,
          Keyword.get(opts, :sink, %Membrane.Debug.Sink{
            handle_buffer: &send(test_process_pid, {:sink_buffer, &1}),
            handle_end_of_stream: fn -> send(test_process_pid, :end_of_stream) end
          })
        )
      ]
    )
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
