defmodule Membrane.RTC.Engine.Endpoint.Transcoder.TrackDataPublisher do
  @moduledoc false
  use Membrane.Sink

  def_input_pad(:input,
    accepted_format: _any,
    availability: :on_request
  )

  @impl true
  def handle_buffer(Pad.ref(:input, track_id), buffer, _ctx, state) do
    {[notify_parent: {:track_data, track_id, buffer}], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, track_id), _ctx, state) do
    {[notify_parent: {:track_finished, track_id}], state}
  end
end
