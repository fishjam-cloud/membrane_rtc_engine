# This examples show how to split the pipeline into two independent parts using `Membrane.Stream.Plugin`
# To run it, execute `elixir <filename>` in your console

# Installs mix dependencies
Mix.install([
  {:membrane_core, "~> 1.0"},
  {:membrane_stream_plugin, "~> 0.4.0"},
  {:membrane_file_plugin, "~> 0.17.0"},
  {:membrane_opus_plugin, "~> 0.17.0"}
])

# This pipeline is responsible for downloading the content from our static repository and
# prepares it for playback. Normally, decoder would be instantly followed by a player, but in this case
# we are serializing the stream and saving it to a file
defmodule Sender do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    spec =
      child(:source, %Membrane.Hackney.Source{
        location:
          "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/ffmpeg-testsrc.h264",
        hackney_opts: [follow_redirect: true]
      })
      |> child(:parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{framerate: {30, 1}},
        output_alignment: :au
      })
      |> child(:decoder, Membrane.H264.FFmpeg.Decoder)
      |> child(:serializer, Membrane.Stream.Serializer)
      |> child(:sink, %Membrane.File.Sink{location: "example.msr"})

    {[spec: spec], %{}}
  end

  # These two `handle_element_end_of_stream/3` clauses are only used to terminate the pipeline after processing finished
  # This part is considered the business logic, you don't need to worry about it in this example
  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end

# Following the completion of the Sender pipeline, we are going to read the saved stream and play it
defmodule Receiver do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    spec =
      child(:source, %Membrane.File.Source{location: "example.msr"})
      |> child(:deserializer, Membrane.Stream.Deserializer)
      |> child(:player, Membrane.SDL.Player)

    {[spec: spec], %{}}
  end

  # These two `handle_element_end_of_stream/3` clauses are only used to terminate the pipeline after processing finished
  # This part is considered the business logic, you don't need to worry about it in this example
  @impl true
  def handle_element_end_of_stream(:player, _pad, _ctx, state) do
    Receiver.terminate(self())
    {[], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end

# Run the two pipelines one after the other

## Start the Sender and await its completion
{:ok, _supervisor_pid, sender_pid} = Membrane.Pipeline.start_link(Sender)
sender_monitor = Process.monitor(sender_pid)

receive do
  {:DOWN, ^sender_monitor, :process, _pid, reason} ->
    unless reason == :normal,
      do: raise("Saving a stream to a file failed with reason: #{inspect(reason)}")

    IO.puts("Recording has been processed and saved to a file `example.msr`")
after
  2_000 ->
    raise("Saving a stream to a file failed due to timeout")
end

## Started the Receiver and await its completion
IO.puts("Playing the recorded file")
{:ok, _supervisor_pid, receiver_pid} = Membrane.Pipeline.start_link(Receiver)
receiver_monitor = Process.monitor(receiver_pid)

receive do
  {:DOWN, ^receiver_monitor, :process, _pid, reason} ->
    unless reason == :normal,
      do: raise("Playing the recorded stream failed with reason: #{inspect(reason)}")

    IO.puts("Playback finished, terminating")
end
