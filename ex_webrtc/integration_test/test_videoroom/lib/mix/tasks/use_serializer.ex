defmodule Mix.Tasks.UseSerializer do
  @moduledoc "Installs a given version of the Typescript Client and sets appropriate application env"
  use Mix.Task

  require Logger

  def run(args) do
    serializer = get_serializer(args)
    Application.put_env(:test_videoroom, :event_serialization, serializer)

    ts_client = "@fishjam-cloud/ts-client@" <> Application.fetch_env!(:ts_client, serializer)

    {_output, 0} = System.cmd("yarn", ["add", "--dev", ts_client], cd: "assets")
    Logger.info("Installed typescript client with #{serializer} serializer")
  end

  defp get_serializer(args) do
    cond do
      "protobuf" in args -> :protobuf
      "json" in args -> :json
    end
  end
end
