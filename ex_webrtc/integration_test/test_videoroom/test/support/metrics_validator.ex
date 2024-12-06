defmodule TestVideoroom.MetricsValidator do
  @spec validate_report(map()) :: :ok | {:error, String.t()}
  def validate_report(report) do
    endpoint_metrics = find_entries(report, :endpoint_id)

    with 2 <- length(endpoint_metrics) do
      Enum.reduce_while(endpoint_metrics, :ok, &validate_endpoint_metrics/2)
    else
      _length ->
        {:error,
         "Found #{length(endpoint_metrics)} when there should be exactly 2 :endpoint_id entries in #{inspect(report)}"}
    end
  end

  defp validate_endpoint_metrics(metrics, _acc) do
    with true <- Map.has_key?(metrics, :"endpoint.metadata"),
         :ok <- metrics |> find_entries(:candidate_id) |> validate_candidates(),
         :ok <- metrics |> find_entries(:track_id) |> validate_tracks() do
      {:cont, :ok}
    else
      false -> {:halt, {:error, "No :\"endpoint.metadata\" key in endpoint metrics"}}
      {:error, reason} -> {:halt, {:error, "#{reason} in #{inspect(metrics)}"}}
    end
  end

  defp validate_candidates(candidates) do
    with true <- length(candidates) >= 1,
         :ok <- Enum.reduce_while(candidates, :ok, &validate_candidate/2) do
      :ok
    else
      false ->
        {:error, "Found #{length(candidates)} when there should be at least 1 remote candidate"}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_candidate(
         %{
           "remote_candidate.port": port,
           "remote_candidate.candidate_type": type,
           "remote_candidate.address": address,
           "remote_candidate.protocol": protocol
         } = candidate,
         _acc
       ) do
    if is_number(port) and type in [:host, :srflx, :prflx] and is_tuple(address) and
         protocol in [:udp, :tcp] do
      {:cont, :ok}
    else
      {:halt, {:error, "Invalid candidate #{inspect(candidate)}"}}
    end
  end

  defp validate_candidate(candidate, _acc),
    do: {:halt, {:error, "Invalid candidate #{inspect(candidate)}"}}

  defp validate_tracks(tracks) do
    with true <- length(tracks) == 6,
         :ok <- Enum.reduce_while(tracks, :ok, &validate_track/2) do
      :ok
    else
      false -> {:error, "Found #{length(tracks)} when there should be exactly 6 track entries"}
      {:error, _reason} = error -> error
    end
  end

  defp validate_track(
         %{
           "outbound-rtp.bytes_sent_total": bytes_total,
           "outbound-rtp.packets_sent_total": packets_total,
           "outbound-rtp.bytes_sent": bytes_sent,
           "outbound-rtp.packets_sent": packets_sent,
           "outbound-rtp.nack_count": nack_count,
           "outbound-rtp.pli_count": pli_count,
           "outbound-rtp.markers_sent": markers_sent,
           "outbound-rtp.retransmitted_packets_sent": retransmitted_packets,
           "outbound-rtp.retransmitted_bytes_sent": retransmitted_bytes
         } = track,
         _acc
       ) do
    if bytes_total > 0 and packets_total > 0 and
         bytes_sent > 0 and packets_sent > 0 and is_number(nack_count) and is_number(pli_count) and
         is_number(markers_sent) and is_number(retransmitted_bytes) and
         is_number(retransmitted_packets) do
      {:cont, :ok}
    else
      {:halt, {:error, "Invalid outbound track #{inspect(track)}"}}
    end
  end

  defp validate_track(
         %{
           "inbound-rtp.bytes_received_total": bytes_total,
           "inbound-rtp.packets_received_total": packets_total,
           "inbound-rtp.bytes_received": bytes_received,
           "inbound-rtp.packets_received": packets_received,
           "inbound-rtp.nack_count": nack_count,
           "inbound-rtp.pli_count": pli_count,
           "inbound-rtp.markers_received": markers_received,
           "inbound-rtp.codec": codec
         } = track,
         _acc
       ) do
    if bytes_total > 0 and packets_total > 0 and bytes_received > 0 and packets_received > 0 and
         is_number(nack_count) and is_number(pli_count) and is_number(markers_received) and
         codec in ["VP8", "H264", "opus"] do
      {:cont, :ok}
    else
      {:halt, {:error, "Invalid inbound track #{inspect(track)}"}}
    end
  end

  defp validate_track(%{"track.metadata": _metadata}, _acc), do: {:cont, :ok}

  defp validate_track(track, _acc), do: {:halt, {:error, "Invalid track #{inspect(track)}"}}

  defp find_entries(entries, name) do
    entries
    |> Enum.filter(fn
      {{^name, _id}, _v} -> true
      _entry -> false
    end)
    |> Enum.map(fn {_k, v} -> v end)
  end
end
