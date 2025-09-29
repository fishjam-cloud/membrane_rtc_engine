defmodule Membrane.RTC.Engine.Support.TestSinkEndpoint do
  @moduledoc false

  # Endpoint that subscribes on all published tracks and drops them.

  use Membrane.Bin

  require Membrane.Logger

  alias Membrane.RTC.Engine

  alias __MODULE__.Sink

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ],
              owner: [
                spec: pid(),
                description: "Pid of endpoint owner"
              ],
              subscribeMode: [
                spec: :auto | :manual,
                default: :auto,
                description:
                  "Whether endpoint should subscribe automatically to all tracks or manually"
              ],
              handle_buffer: [
                spec: (Buffer.t() -> any()),
                description:
                  "Function with arity 1, that will be called with all buffers handled by the sink endpoint. Result of this function is ignored.",
                default: &Function.identity/1
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request

  @impl true
  def handle_init(_ctx, opts) do
    state =
      opts
      |> Map.from_struct()
      |> Map.merge(%{
        subscribing_tracks: %{}
      })

    {[notify_parent: :ready], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, track_id) = pad, _ctx, state) do
    spec =
      bin_input(pad)
      |> child({:test_sink, track_id}, %Sink{handle_buffer: state.handle_buffer})

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, track_id), _ctx, state) do
    {[remove_children: {:test_sink, track_id}], state}
  end

  @impl true
  def handle_parent_notification({:new_tracks, tracks}, ctx, %{subscribeMode: :auto} = state) do
    {:endpoint, endpoint_id} = ctx.name

    new_subscribing_tracks =
      Map.new(tracks, fn track ->
        ref = Engine.subscribe_async(state.rtc_engine, endpoint_id, track.id)
        {ref, endpoint_id}
      end)

    state = update_in(state.subscribing_tracks, &Map.merge(&1, new_subscribing_tracks))

    {[], state}
  end

  @impl true
  def handle_parent_notification({:subscribe, track_id}, ctx, state) do
    {:endpoint, endpoint_id} = ctx.name
    Engine.subscribe(state.rtc_engine, endpoint_id, track_id)

    {[], state}
  end

  @impl true
  def handle_parent_notification(_msg, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:subscribe_result, subscribe_ref, result}, _ctx, state) do
    {:ok, _track} = result
    {endpoint_id, subscribing_tracks} = Map.pop(state.subscribing_tracks, subscribe_ref)

    send(state.owner, endpoint_id)

    {[], %{state | subscribing_tracks: subscribing_tracks}}
  end
end
