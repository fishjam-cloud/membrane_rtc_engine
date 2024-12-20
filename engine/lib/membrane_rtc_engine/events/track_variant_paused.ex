defmodule Membrane.RTC.Engine.Event.TrackVariantPaused do
  @moduledoc """
  Event sent whenever track variant was paused.
  """

  alias Membrane.RTC.Engine.Track

  @derive Membrane.EventProtocol

  @typedoc """
  Type describing TrackVariantPaused event.

  * `variant` - variant that has been paused
  * `reason` - specifies whether the track has been paused automatically due to inactivity or on purpose due to being muted
  """
  @type t :: %__MODULE__{
          variant: Track.variant(),
          reason: :inactive | :muted
        }

  @enforce_keys [:variant, :reason]
  defstruct @enforce_keys
end
