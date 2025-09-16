defmodule Membrane.RTC.Engine.Endpoint.Agent.Timestamper do
  @moduledoc """
  Membrane element responsible for assigning pts values
  to an incoming agent track.

  If a buffer's arrival time is greater
  than the previous buffer's end timestamp + @max_jitter_duration,
  then its start timestamp is based on its arrival time.
  Otherwise its start timestamp is the end timestamp of the previous buffer.
  """

  use Membrane.Endpoint

  alias Membrane.RawAudio
  alias Membrane.Opus

  @max_jitter_duration Membrane.Time.milliseconds(100)

  def_input_pad :input,
    accepted_format: RawAudio,
    availability: :always

  def_output_pad :output,
    accepted_format: RawAudio,
    availability: :always,
    flow_control: :push

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{next_pts: 0, start_ts: nil, stream_format: nil}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _context, state) do
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_buffer(_pad, buffer, ctx, state) do
    stream_format = get_in(ctx, [:pads, :output, :stream_format])
    state = maybe_reset_pts(state)
    buffer = %Membrane.Buffer{buffer | pts: state.next_pts}

    {[buffer: {:output, buffer}], update_next_pts(buffer, stream_format, state)}
  end

  defp maybe_reset_pts(%{next_pts: next_pts, start_ts: start_ts} = state) do
    now_ts = Membrane.Time.os_time()
    start_ts = start_ts || now_ts
    arrival_time = now_ts - start_ts

    next_pts =
      if arrival_time > next_pts + @max_jitter_duration do
        arrival_time
      else
        next_pts
      end

    %{state | start_ts: start_ts, next_pts: next_pts}
  end

  defp update_next_pts(
         buffer,
         stream_format,
         %{next_pts: next_pts} = state
       ),
       do: %{state | next_pts: next_pts + get_duration(buffer, stream_format)}

  defp get_duration(buffer, %RawAudio{} = stream_format),
    do: RawAudio.bytes_to_time(byte_size(buffer.payload), stream_format)

  defp get_duration(buffer, %Opus{}), do: buffer.metadata.duration
end
