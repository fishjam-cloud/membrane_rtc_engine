defmodule Membrane.RTC.Engine.Support.TestEndpoint do
  @moduledoc false

  use Membrane.Bin

  require Membrane.Logger

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ],
              owner: [
                spec: pid(),
                default: nil,
                description: "Pid of owner of endpoint"
              ],
              delay_termination: [
                spec: pos_integer(),
                default: nil,
                description: "Delay of endpoint termination in milliseconds"
              ]

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request

  @impl true
  def handle_init(_ctx, opts) do
    state = Map.from_struct(opts)

    Process.flag(:trap_exit, true)

    {[], state}
  end

  @impl true
  def handle_parent_notification({:execute_actions, actions}, _ctx, state), do: {actions, state}

  @impl true
  def handle_parent_notification(_message, _ctx, %{owner: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification(message, _ctx, state) do
    send(state.owner, message)
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, %{delay_termination: nil} = state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_terminate_request(_ctx, %{delay_termination: delay} = state) do
    # Allows to test race condtition connected to adding new endpoint
    # while the old one with the same id is in terminating state
    Process.send_after(self(), {:exit_now, :normal}, delay)

    {[], state}
  end

  def handle_info({:EXIT, _pid, reason}, _ctx, %{delay_termination: delay} = state)
      when is_integer(delay) do
    # Allows to test race condtition which occurs when a crash group
    # is partially down, before handle_crash_group_down is called
    Process.send_after(self(), {:exit_now, reason}, delay)
    {[], state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, _ctx, state) do
    {[terminate: reason], state}
  end

  @impl true
  def handle_info({:exit_now, reason}, _ctx, state) do
    {[terminate: reason], state}
  end
end
