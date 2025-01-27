defmodule Mix.Tasks.UseSerializer do
  @moduledoc "Installs a given version of the Typescript Client and sets appropriate application env"
  use Mix.Task

  require Logger

  def run(_args) do
    Application.put_env(:test_videoroom, :event_serialization, :protobuf)
  end
end
