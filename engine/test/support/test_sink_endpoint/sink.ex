defmodule Membrane.RTC.Engine.Support.TestSinkEndpoint.Sink do
  @moduledoc """
  A custom Sink element for the TestSinkEndpoint, that sends
  RequestTrackVariant message, once input track is connected,
  and is can be provided with custom `handle_buffer` function,
  that is called on each buffer.
  """
  use Membrane.Sink

  def_input_pad :input,
    accepted_format: _any,
    availability: :always

  alias Membrane.RTC.Engine.Event.RequestTrackVariant

  def_options handle_buffer: [
                spec: (Buffer.t() -> any()),
                description:
                  "Function with arity 1, that will be called with all buffers handled by this sink. Result of this function is ignored."
              ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], Map.from_struct(opts)}
  end

  @impl true
  def handle_playing(_ctx, state) do
    request_track_variant = {Pad.ref(:input), %RequestTrackVariant{variant: :high}}

    {[event: request_track_variant], state}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    state.handle_buffer.(buffer)

    {[], state}
  end
end
