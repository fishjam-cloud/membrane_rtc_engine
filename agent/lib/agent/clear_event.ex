defmodule Membrane.RTC.Engine.Endpoint.Agent.InterruptEvent do
  @moduledoc """
  Event sent when an agent interruption is triggered.

  Its handlers should clear any queued buffers and reset
  their state to correctly calculate new pts values for incoming buffers.
  """

  @derive Membrane.EventProtocol
  defstruct []
end
