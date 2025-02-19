defmodule TestVideoroomWeb.RoomChannel do
  use TestVideoroomWeb, :channel

  require Logger

  @impl true
  def join("room" = room_id, params, socket) do
    video_codec = parse_codec(Map.get(params, "videoCodec"))
    case :global.whereis_name(room_id) do
      :undefined -> TestVideoroom.Room.start(name: {:global, room_id})
      pid -> {:ok, pid}
    end
    |> case do
      {:ok, room} ->
        join_room(room_id, room, socket, video_codec)

      {:error, {:already_started, _pid}} ->
        room = :global.whereis_name(room_id)
        join_room(room_id, room, socket, video_codec)

      {:error, reason} ->
        Logger.error("""
        Failed to start room.
        Room: #{inspect(room_id)}
        Reason: #{inspect(reason)}
        """)

        {:error, %{reason: "failed to start room"}}
    end
  end


  defp parse_codec("vp8") do
    :VP8
  end
  
  defp parse_codec("h264") do
    :H264
  end
  
  defp parse_codec(nil) do
    nil
  end


  defp join_room(room_id, room, socket, video_codec) do
    peer_id = "#{UUID.uuid4()}"
    Process.monitor(room)
    TestVideoroom.Room.add_peer_channel(room, self(), peer_id, video_codec)
    {:ok, Phoenix.Socket.assign(socket, %{room_id: room_id, room: room, peer_id: peer_id, video_codec: video_codec})}
  end

  @impl true
  def handle_in("mediaEvent", {:binary, media_event}, socket) do
    send(socket.assigns.room, {:media_event, socket.assigns.peer_id, media_event})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_event, event}, socket) do
    push(socket, "mediaEvent", {:binary, event})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, room, :normal}, %{assigns: %{room: room}} = state) do
    {:stop, :normal, state}
  end
end
