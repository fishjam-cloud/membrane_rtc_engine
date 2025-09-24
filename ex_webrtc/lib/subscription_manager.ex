defmodule Membrane.RTC.Engine.Endpoint.ExWebRTC.SubscriptionManager do
  @moduledoc """
  Manages track subscriptions for ExWebRTC endpoints in both auto and manual modes.
  """

  use Bunch.Access

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.{Endpoint, Track}
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC.Track, as: EndpointTrack

  @type subscribe_mode :: :auto | :manual

  @type t :: %__MODULE__{
          rtc_engine: Endpoint.id(),
          subscribe_mode: subscribe_mode(),
          subscribed_tracks: MapSet.t(Track.id()),
          subscribed_endpoints: MapSet.t(Endpoint.id())
        }
  @enforce_keys [:rtc_engine, :subscribe_mode]

  defstruct @enforce_keys ++ [subscribed_tracks: MapSet.new(), subscribed_endpoints: MapSet.new()]

  @doc """
  Creates a new subscription manager.
  """
  @spec new(Endpoint.id(), subscribe_mode()) :: t()
  def new(rtc_engine, subscribe_mode) do
    %__MODULE__{rtc_engine: rtc_engine, subscribe_mode: subscribe_mode}
  end

  @doc """
  Handles peer subscription in manual mode.
  """
  @spec subscribe_endpoint(t(), String.t()) :: {[Track.t()], t()}
  def subscribe_endpoint(
        %{rtc_engine: rtc_engine, subscribe_mode: :manual} = manager,
        endpoint_id
      ) do
    tracks_to_add =
      rtc_engine
      |> Engine.get_tracks()
      |> Enum.filter(fn t -> t.origin == endpoint_id end)

    manager = %{
      manager
      | subscribed_endpoints: MapSet.put(manager.subscribed_endpoints, endpoint_id)
    }

    {tracks_to_add, manager}
  end

  def subscribe_endpoint(%{subscribe_mode: :auto} = manager, _endpoint_id) do
    {[], manager}
  end

  @doc """
  Handles track subscription in manual mode.
  """
  @spec subscribe_tracks(t(), [Track.id()]) :: {[Track.t()], t()}
  def subscribe_tracks(%{rtc_engine: rtc_engine, subscribe_mode: :manual} = manager, track_ids) do
    tracks_to_add =
      rtc_engine
      |> Engine.get_tracks()
      |> Enum.filter(&Enum.member?(track_ids, &1.id))

    subscribed_tracks = Enum.map(tracks_to_add, fn t -> t.id end)

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
  @spec handle_new_tracks(t(), [Track.t()]) :: {map(), t()}
  def handle_new_tracks(manager, new_tracks) do
    new_tracks_map =
      Map.new(new_tracks, &{&1.id, %EndpointTrack{status: :pending, engine_track: &1}})

    filtered_tracks = filter_subscribed_new_tracks(manager, new_tracks_map)

    {filtered_tracks, manager}
  end

  @doc """
  Removes tracks from the manager.
  """
  @spec remove_tracks(t(), [Track.t()]) :: t()
  def remove_tracks(manager, tracks) do
    track_ids = Enum.map(tracks, & &1.id)

    manager
    |> update_in([:subscribed_tracks], &MapSet.difference(&1, MapSet.new(track_ids)))
  end

  defp filter_subscribed_new_tracks(%{subscribe_mode: :auto}, new_tracks), do: new_tracks

  defp filter_subscribed_new_tracks(%{subscribe_mode: :manual} = manager, new_tracks) do
    new_tracks
    |> Enum.filter(fn {id, %EndpointTrack{engine_track: t}} ->
      MapSet.member?(manager.subscribed_endpoints, t.origin) or
        MapSet.member?(manager.subscribed_tracks, id)
    end)
    |> Map.new()
  end
end
