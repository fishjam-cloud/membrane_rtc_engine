defmodule TestVideoroom.MetricsScraper do
  @moduledoc false

  use GenServer, restart: :temporary

  alias Membrane.TelemetryMetrics.Reporter

  @scrape_interval 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, @scrape_interval, name: __MODULE__)
  end

  @impl true
  def init(scrape_interval) do
    send(self(), :scrape)

    {:ok, %{scrape_interval: scrape_interval, subscriptions: []}}
  end

  @impl true
  def handle_info(:scrape, state) do
    report = Reporter.scrape(ExWebrtcMetricsReporter)

    Process.send_after(self(), :scrape, state.scrape_interval)

    Enum.each(state.subscriptions, &send(&1, {:metrics, report}))

    {:noreply, state}
  end

  @impl true
  def handle_info({:subscribe, pid}, state) do
    Reporter.scrape_and_cleanup(ExWebrtcMetricsReporter)
    state = update_in(state.subscriptions, &[pid | &1])
    {:noreply, state}
  end
end
