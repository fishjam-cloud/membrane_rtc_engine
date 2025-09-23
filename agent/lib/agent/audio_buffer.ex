defmodule Membrane.RTC.Engine.Endpoint.Agent.AudioBuffer do
  @moduledoc """
  Membrane element responsible for buffering incoming audio chunks,
  as they come in bursts from the TTS model.
  """

  use Membrane.Filter

  require Membrane.Logger

  alias Membrane.Opus
  alias Membrane.RawAudio

  @default_max_buffered_duration Membrane.Time.seconds(10)

  def_options max_buffered_duration: [
                spec: Membrane.Time.t(),
                description:
                  "Maximum duration of audio that can be buffered. Extra audio is dropped.",
                default: @default_max_buffered_duration
              ]

  def_input_pad :input,
    accepted_format: any_of(RawAudio, Opus),
    availability: :always

  def_output_pad :output,
    accepted_format: any_of(RawAudio, Opus),
    availability: :always,
    demand_unit: :buffers,
    flow_control: :manual

  @type queue_element :: Membrane.Buffer.t() | :end_of_stream

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       queue: Qex.new(),
       queue_duration: 0,
       demand: 0,
       max_queue_duration: opts.max_buffered_duration
     }}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    state
    |> Map.update!(:queue, &Qex.push(&1, :end_of_stream))
    |> do_handle_demand()
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    if state.queue_duration + buffer.metadata.duration <= state.max_queue_duration do
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
  def handle_parent_notification(:clear_queue, _ctx, state) do
    {[], clear_queue(state)}
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
      {element, queue} = Qex.pop!(state.queue)

      state =
        state
        |> Map.put(:queue, queue)
        |> Map.put(:demand, demand - 1)
        |> Map.update!(:queue_duration, &(&1 - get_element_duration(element)))

      do_handle_demand(state, [to_action(element) | buffers])
    end
  end

  @spec get_element_duration(queue_element()) :: integer()
  defp get_element_duration(:end_of_stream), do: 0

  defp get_element_duration(buffer), do: buffer.metadata.duration

  @spec to_action(queue_element()) :: Membrane.Element.Action.t()
  defp to_action(:end_of_stream), do: {:end_of_stream, :output}

  defp to_action(buffer), do: {:buffer, {Pad.ref(:output), buffer}}

  defp conclude_handle_demand(state, actions) do
    {Enum.reverse(actions), state}
  end

  defp clear_queue(state) do
    queue = state.queue |> Enum.filter(&(&1 == :end_of_stream)) |> Qex.new()

    %{state | queue: queue, queue_duration: 0}
  end
end
