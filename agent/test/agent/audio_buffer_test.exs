defmodule Membrane.RTC.Engine.Endpoint.Agent.AudioBufferTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec

  alias Membrane.Buffer
  alias Membrane.Testing

  alias Membrane.RTC.Engine.Endpoint.Agent.AudioBuffer

  @buffer_duration Membrane.Time.milliseconds(10)
  @fake_buffer_duration Membrane.Time.milliseconds(100)

  test "sends all buffers" do
    payload = [1, 2, 3, 4] |> Enum.map(&<<&1>>)

    start_pipeline(payload)

    Process.sleep(250)

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

  test "drops buffers if over the limit" do
    payload = 1..200 |> Enum.map(&<<&1>>)

    start_pipeline(payload, realtimer?: true)

    for data <- Enum.take(payload, 100) do
      assert_receive_buffer(data)
    end

    count = count_sink_buffers()
    assert count < 100
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
        |> child(:sink, %Membrane.Debug.Sink{
          handle_buffer: &send(test_process_pid, {:sink_buffer, &1}),
          handle_end_of_stream: fn -> send(test_process_pid, :end_of_stream) end
        })
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
        if length(state.buffers) == 0, do: [end_of_stream: :output], else: []

      {buffers ++ maybe_eos, state}
    end
  end
end
