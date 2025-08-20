defmodule Membrane.RTC.Engine.Endpoint.Agent.Test.BufferForwarder do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.RTC.Engine

  alias Fishjam.AgentRequest
  alias Fishjam.AgentRequest.{AddTrack, RemoveTrack, TrackData}
  alias Fishjam.AgentRequest.AddTrack.CodecParameters
  alias Fishjam.Notifications.Track

  @agent_id "agent"

  def_options rtc_engine: [
                spec: pid()
              ],
              track_id: [
                spec: String.t()
              ],
              sample_rate: [
                spec: non_neg_integer()
              ],
              encoding: [
                spec: [:opus | :pcm16]
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :always,
    flow_control: :manual,
    demand_unit: :buffers

  @sample_interval 1

  @impl true
  def handle_init(_ctx, opts) do
    state = opts |> Map.from_struct() |> Map.put(:eos?, false)
    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    track = %Track{
      id: state.track_id,
      type: :TRACK_TYPE_AUDIO,
      metadata: Jason.encode!(%{name: "It's a track", source: "macbook camera"})
    }

    params = %CodecParameters{
      encoding: to_proto_encoding(state.encoding),
      sample_rate: state.sample_rate,
      channels: 1
    }

    add_track = %AddTrack{
      track: track,
      codec_params: params
    }

    message_agent(:add_track, add_track, state.rtc_engine)

    Process.send_after(self(), :demand, @sample_interval)

    {[demand: {:input, 1}], state}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    message_agent(
      :track_data,
      %TrackData{
        track_id: state.track_id,
        data: buffer.payload
      },
      state.rtc_engine
    )

    {[], state}
  end

  @impl true
  def handle_info(:demand, _ctx, %{eos?: true} = state) do
    {[], state}
  end

  @impl true
  def handle_info(:demand, _ctx, state) do
    Process.send_after(self(), :demand, @sample_interval)

    {[demand: {:input, 1}], state}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    message_agent(:remove_track, %RemoveTrack{track_id: state.track_id}, state.rtc_engine)

    {[], %{state | eos?: true}}
  end

  defp message_agent(event_name, message, engine) do
    request = %AgentRequest{
      content: {event_name, message}
    }

    Engine.message_endpoint(engine, @agent_id, {:agent_notification, request})
  end

  defp to_proto_encoding(:pcm16), do: :TRACK_ENCODING_PCM16
  defp to_proto_encoding(:opus), do: :TRACK_ENCODING_OPUS
end
