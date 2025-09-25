defmodule Membrane.RTC.Engine.Endpoint.Agent.Timestamper do
  @moduledoc """
  Membrane element responsible for assigning pts values
  to an incoming agent track.

  If a buffer's arrival time is greater
  than the previous buffer's end timestamp + @max_jitter_duration,
  then its start timestamp is based on its arrival time.
  Otherwise its start timestamp is the end timestamp of the previous buffer.
  """

  use Membrane.Filter

  alias Membrane.Opus
  alias Membrane.RawAudio

  alias Membrane.RTC.Engine.Endpoint.Agent.InterruptEvent

  @max_jitter_duration Membrane.Time.milliseconds(100)

  def_input_pad :input,
    accepted_format: any_of(RawAudio, Opus),
    flow_control: :auto,
    availability: :always

  def_output_pad :output,
    accepted_format: any_of(RawAudio, Opus),
    availability: :always,
    flow_control: :auto

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{next_pts: nil, start_timestamp: nil, stream_format: nil}}
  end

  @impl true
  def handle_buffer(_pad, buffer, ctx, state) do
    stream_format = get_in(ctx, [:pads, :output, :stream_format])

    {actions, state} = maybe_reset_pts(state)

    buffer =
      %Membrane.Buffer{buffer | pts: state.next_pts} |> update_buffer_duration(stream_format)

    {actions ++ [buffer: {:output, buffer}], update_next_pts(buffer, state)}
  end

  @impl true
  def handle_parent_notification(:interrupt_track, _ctx, state) do
    {[event: {:output, %InterruptEvent{}}], %{state | next_pts: nil}}
  end

  defp maybe_reset_pts(%{start_timestamp: nil} = state) do
    {[], %{state | start_timestamp: Membrane.Time.os_time(), next_pts: 0}}
  end

  defp maybe_reset_pts(%{next_pts: next_pts, start_timestamp: start_timestamp} = state) do
    arrival_time = Membrane.Time.os_time() - start_timestamp

    if next_pts == nil or arrival_time > next_pts + @max_jitter_duration do
      {[event: {:output, %Membrane.Realtimer.Events.Reset{}}], %{state | next_pts: arrival_time}}
    else
      {[], state}
    end
  end

  defp update_next_pts(
         buffer,
         %{next_pts: next_pts} = state
       ),
       do: %{state | next_pts: next_pts + buffer.metadata.duration}

  defp update_buffer_duration(buffer, %RawAudio{} = stream_format) do
    size = RawAudio.bytes_to_time(byte_size(buffer.payload), stream_format)

    %{buffer | metadata: Map.put(buffer.metadata, :duration, size)}
  end

  defp update_buffer_duration(buffer, %Opus{}) do
    buffer
  end
end
