defmodule Membrane.RTC.Engine.Endpoint.Forwarder.TestPipeline do
  @moduledoc false

  use Membrane.Pipeline

  @impl true
  def start_link(options) do
    Membrane.Pipeline.start_link(__MODULE__, options, name: TestPipeline)
  end

  @impl true
  def handle_init(_ctx, options) do
    {[spec: options.spec], %{owner: options.owner}}
  end

  @impl true
  def handle_crash_group_down(group_name, ctx, state) do
    send(state.owner, {:group_crash, group_name, ctx.crash_reason})

    {[], state}
  end
end
