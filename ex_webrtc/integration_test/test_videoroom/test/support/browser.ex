defmodule TestVideoroom.Browser do
  use GenServer
  require Logger

  @get_stats_duration 2_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def get_playwright(browser) do
    GenServer.call(browser, :get_playwright)
  end

  def join(browser, button, params \\ "") do
    GenServer.call(browser, {:join, button, params})
  end

  def click(browser, button) do
    GenServer.call(browser, {:click, button})
  end

  def get_stats(browser, button) do
    GenServer.call(browser, {:get_stats, button})
  end

  def fetch_stats_async(browser, button) do
    GenServer.cast(browser, {:fetch_stats_async, button})
  end

  def receive_stats(browser_id) do
    receive do
      {^browser_id, stats} -> stats
    end
  end

  def leave(browser) do
    playwright = get_playwright(browser)

    Playwright.Browser.close(playwright)
  end

  @impl true
  def init(opts) do
    default_browser_args = [
      "--use-fake-device-for-media-stream",
      "--use-fake-ui-for-media-stream"
    ]

    additional_args = Map.get(opts, :args, [])

    launch_options = %{
      args: default_browser_args ++ additional_args,
      headless: Map.get(opts, :headless, true)
    }

    Application.put_env(:playwright, LaunchOptions, launch_options)

    {:ok, browser} = Playwright.launch(:chromium)

    page = browser |> Playwright.Browser.new_page()

    _response = Playwright.Page.goto(page, opts.target_url)

    Playwright.Page.on(page, :console, fn _e ->
      # useful for debugging
      # IO.inspect(e.params.message, label: options.id)
      :ok
    end)

    {:ok, %{browser: browser, page: page, id: opts.id, receiver: opts.receiver}}
  end

  @impl true
  def handle_call(:get_playwright, _from, state) do
    {:reply, state.browser, state}
  end

  @impl true
  def handle_call({:join, button, params} = action, _from, state) do
    Logger.info("mustang: #{state.id}, action: #{inspect(action)}")

    url = Playwright.Page.url(state.page) <> params
    Playwright.Page.goto(state.page, url)

    state.page
    |> Playwright.Page.locator("[id=#{button}]")
    |> Playwright.Locator.click()

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:click, button} = action, _from, state) do
    Logger.info("mustang: #{state.id}, action: #{inspect(action)}")
    :ok = Playwright.Page.click(state.page, "[id=#{button}]")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_stats, button} = action, from, state) do
    Logger.info("mustang: #{state.id}, action: #{inspect(action)}")

    :ok = Playwright.Page.click(state.page, "[id=#{button}]")

    Process.send_after(self(), {:do_get_stats, {:reply, from}}, @get_stats_duration)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:fetch_stats_async, button} = action, state) do
    Logger.info("mustang: #{state.id}, action: #{inspect(action)}")

    :ok = Playwright.Page.click(state.page, "[id=#{button}]")

    Process.send_after(self(), {:do_get_stats, :async}, @get_stats_duration)

    {:noreply, state}
  end

  @impl true
  def handle_info({:do_get_stats, reply} = action, state) do
    Logger.info("mustang: #{state.id}, action: #{inspect(action)}")

    stats = get_stats(state.page)

    case reply do
      {:reply, pid} -> GenServer.reply(pid, stats)
      :async -> send(state.receiver, {state.id, stats})
    end

    {:noreply, state}
  end

  defp get_stats(page) do
    page
    |> Playwright.Page.text_content("[id=data]")
    |> case do
      "uninitialized" ->
        {:error, :uninitialized}

      "undefined" ->
        {:error, :undefined}

      "Room error." <> reason ->
        {:error, reason}

      data ->
        Jason.decode!(data)
    end
  end
end
