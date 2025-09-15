defmodule Membrane.RTC.Engine.Endpoint.Agent.Timestamper do
  use Membrane.Endpoint

  alias Membrane.RawAudio

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
    state = update_late_pts(state)
    buffer = %Membrane.Buffer{buffer | pts: state.next_pts}

    {[buffer: {:output, buffer}], update_next_pts(buffer.payload, stream_format, state)}
  end

  defp update_late_pts(%{next_pts: next_pts, start_ts: start_ts} = state) do
    now_ts = Membrane.Time.os_time()
    start_ts = start_ts || now_ts
    next_pts = max(next_pts, now_ts - start_ts)

    %{state | start_ts: start_ts, next_pts: next_pts}
  end

  defp update_next_pts(
         payload,
         stream_format,
         %{next_pts: next_pts} = state
       ) do
    duration = RawAudio.bytes_to_time(byte_size(payload), stream_format)
    %{state | next_pts: next_pts + duration}
  end
end
