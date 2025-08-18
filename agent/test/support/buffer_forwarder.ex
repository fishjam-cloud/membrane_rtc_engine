defmodule Membrane.RTC.Engine.Endpoint.Agent.Test.BufferForwarder do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.RTC.Engine

  alias Fishjam.Notifications.Track
  alias Fishjam.AgentRequest
  alias Fishjam.AgentRequest.{AddTrack, TrackData}
  alias Fishjam.AgentRequest.AddTrack.CodecParameters

  @agent_id "agent"

  def_options rtc_engine: [
                spec: pid()
              ],
              track_id: [
                spec: String.t()
              ],
              sample_rate: [
                spec: non_neg_integer()
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :always

  @impl true
  def handle_init(_ctx, options) do
    {[], Map.from_struct(options)}
  end

  @impl true
  def handle_playing(_ctx, state) do
    track = %Track{
      id: state.track_id,
      type: :TRACK_TYPE_AUDIO,
      metadata: "It's a track!"
    }

    params = %CodecParameters{
      encoding: :TRACK_ENCODING_PCM16,
      sample_rate: state.sample_rate,
      channels: 1
    }

    add_track = %AddTrack{
      track: track,
      codec_params: params
    }

    message_agent(:add_track, add_track, state)

    {[], state}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    message_agent(:track_data, %TrackData{
      track_id: state.track_id,
      data: buffer.payload
    }, state)
    {[], state}
  end

  defp message_agent(name, message, state) do
    request = %AgentRequest{
      content: {name, message}
    }

    Engine.message_endpoint(state.rtc_engine, @agent_id,
    {:agent_notification, request})
  end
end
