defmodule Membrane.RTC.Engine.Endpoint.Agent.AudioBuffer do
  @moduledoc """
  Membrane element responsible for buffering incoming audio chunks,
  as they come in bursts from the TTS model.
  """

  use Membrane.Filter

  require Membrane.Logger

  alias Membrane.Opus
  alias Membrane.RawAudio

  @max_buffered_duration Membrane.Time.seconds(10)

  def_input_pad :input,
    accepted_format: any_of(RawAudio, Opus),
    availability: :always

  def_output_pad :output,
    accepted_format: any_of(RawAudio, Opus),
    availability: :always,
    demand_unit: :buffers,
    flow_control: :manual

  @impl true
  def handle_init(_ctx, _opts) do
    {[],
     %{
       queue: Qex.new(),
       queue_duration: 0,
       demand: 0
     }}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {[end_of_stream: :output], state}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    if state.queue_duration + buffer.metadata.duration <= @max_buffered_duration do
      state =
        state
        |> Map.update!(:queue, &Qex.push(&1, buffer))
        |> Map.update!(:queue_duration, &(&1 + buffer.metadata.duration))

      do_handle_demand(state)
    else
      Membrane.Logger.warning("Audio Buffer dropping buffer - queue too long")
      {[], state}
    end
  end

  @impl true
  def handle_demand(Pad.ref(:output), size, :buffers, _ctx, state) do
    state
    |> Map.update!(:demand, &(&1 + size))
    |> do_handle_demand()
  end

  defp do_handle_demand(state, buffers \\ [])

  defp do_handle_demand(%{demand: 0} = state, buffers) do
    conclude_handle_demand(state, buffers)
  end

  defp do_handle_demand(%{demand: demand} = state, buffers) do
    if Enum.empty?(state.queue) do
      conclude_handle_demand(state, buffers)
    else
      {buffer, queue} = Qex.pop!(state.queue)

      state =
        state
        |> Map.put(:queue, queue)
        |> Map.put(:demand, demand - 1)
        |> Map.update!(:queue_duration, &(&1 - buffer.metadata.duration))

      do_handle_demand(state, [buffer | buffers])
    end
  end

  defp conclude_handle_demand(state, []) do
    {[], state}
  end

  defp conclude_handle_demand(state, buffers) do
    actions = [buffer: {Pad.ref(:output), Enum.reverse(buffers)}]

    {actions, state}
  end
end
