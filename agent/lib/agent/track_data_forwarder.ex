defmodule Membrane.RTC.Engine.Endpoint.Agent.TrackDataForwarder do
  @moduledoc false
  use Membrane.Source

  alias Membrane.{Opus, RawAudio}

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request,
    flow_control: :push

  @impl true
  def handle_init(_ctx, _opts) do
    state = %{
      stream_formats: %{}
    }

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, track_id) = pad, _ctx, state) do
    case pop_in(state, [:stream_formats, track_id]) do
      {nil, state} -> {[], state}
      {format, state} -> {[stream_format: {pad, format}], state}
    end
  end

  @impl true
  def handle_parent_notification({:new_track, track_id, codec_params}, ctx, state) do
    format = get_stream_format(codec_params)
    pad = Pad.ref(:output, track_id)

    case Map.has_key?(ctx.pads, pad) do
      true -> {[stream_format: {pad, format}], state}
      false -> {[], put_in(state, [:stream_formats, track_id], format)}
    end
  end

  @impl true
  def handle_parent_notification({:track_data, track_id, data}, ctx, state) do
    case get_in(ctx, [:pads, Pad.ref(:output, track_id), :stream_format]) do
      # The pad exists, and stream_format has been set
      %{} ->
        buffer = %Membrane.Buffer{payload: data}
        {[buffer: {Pad.ref(:output, track_id), buffer}], state}

      nil ->
        {[], state}
    end
  end

  defp get_stream_format(%{encoding: :pcm16, sample_rate: sample_rate}) do
    %RawAudio{channels: 1, sample_rate: sample_rate, sample_format: :s16le}
  end

  defp get_stream_format(%{encoding: :opus}) do
    %Opus{channels: 1, self_delimiting?: false}
  end
end
