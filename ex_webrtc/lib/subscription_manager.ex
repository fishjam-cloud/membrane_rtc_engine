defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.SubscriptionManager do
  @moduledoc """
  Manages track subscriptions for ExWebRTC endpoints in both auto and manual modes.
  """

  use Bunch.Access

  alias Membrane.RTC.Engine.Track

  @type subscribe_mode :: :auto | :manual

  @type t :: %__MODULE__{
          subscribe_mode: subscribe_mode(),
          known_tracks: %{},
          subscribed_tracks: MapSet.t(Track.id()),
          subscribed_endpoints: MapSet.t(String.t())
        }

  defstruct subscribe_mode: :auto,
            known_tracks: %{},
            subscribed_tracks: MapSet.new(),
            subscribed_endpoints: MapSet.new()

  @doc """
  Creates a new subscription manager.
  """
  @spec new(subscribe_mode()) :: t()
  def new(subscribe_mode) do
    %__MODULE__{subscribe_mode: subscribe_mode}
  end

  @doc """
  Handles peer subscription in manual mode.
  """
  @spec subscribe_peer(t(), String.t()) :: {[Track.t()], t()}
  def subscribe_peer(%{subscribe_mode: :manual} = manager, endpoint_id) do
    tracks_to_add =
      manager.known_tracks
      |> Map.values()
      |> Enum.filter(fn %{engine_track: t} -> t.origin == endpoint_id end)
      |> Enum.map(& &1.engine_track)

    manager = %{
      manager
      | subscribed_endpoints: MapSet.put(manager.subscribed_endpoints, endpoint_id)
    }

    {tracks_to_add, manager}
  end

  def subscribe_peer(%{subscribe_mode: :auto} = manager, _endpoint_id) do
    {[], manager}
  end

  @doc """
  Handles track subscription in manual mode.
  """
  @spec subscribe_tracks(t(), [Track.id()]) :: {[Track.t()], t()}
  def subscribe_tracks(%{subscribe_mode: :manual} = manager, track_ids) do
    subscribed_tracks =
      track_ids
      |> Enum.filter(fn t -> Map.has_key?(manager.known_tracks, t) end)

    tracks_to_add = Enum.map(subscribed_tracks, &manager.known_tracks[&1].engine_track)

    manager = %{
      manager
      | subscribed_tracks: MapSet.union(manager.subscribed_tracks, MapSet.new(subscribed_tracks))
    }

    {tracks_to_add, manager}
  end

  def subscribe_tracks(%{subscribe_mode: :auto} = manager, _track_ids) do
    {[], manager}
  end

  @doc """
  Updates known tracks and returns filtered tracks for subscription.
  """
  @spec handle_new_tracks(t(), [Track.t()]) ::
          {%{}, t()}
  def handle_new_tracks(manager, new_tracks) do
    alias Membrane.RTC.Engine.Endpoint.ExWebRTC.Track, as: EndpointTrack

    new_tracks_map =
      new_tracks
      |> Map.new(&{&1.id, %EndpointTrack{status: :pending, engine_track: &1}})

    filtered_tracks = filter_subscribed_new_tracks(manager, new_tracks_map)
    manager = %{manager | known_tracks: Map.merge(manager.known_tracks, new_tracks_map)}

    {filtered_tracks, manager}
  end

  @doc """
  Removes tracks from the manager.
  """
  @spec remove_tracks(t(), [Track.t()]) :: t()
  def remove_tracks(manager, tracks) do
    track_ids = Enum.map(tracks, & &1.id)

    manager
    |> update_in([:known_tracks], &Map.drop(&1, track_ids))
    |> update_in([:subscribed_tracks], &MapSet.difference(&1, MapSet.new(track_ids)))
  end

  defp filter_subscribed_new_tracks(%{subscribe_mode: :auto}, new_tracks), do: new_tracks

  defp filter_subscribed_new_tracks(%{subscribe_mode: :manual} = manager, new_tracks) do
    alias Membrane.RTC.Engine.Endpoint.ExWebRTC.Track, as: EndpointTrack

    new_tracks
    |> Enum.filter(fn {id, %EndpointTrack{engine_track: t}} ->
      MapSet.member?(manager.subscribed_endpoints, t.origin) or
        MapSet.member?(manager.subscribed_tracks, id)
    end)
    |> Map.new()
  end
end
