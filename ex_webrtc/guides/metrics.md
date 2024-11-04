# Metrics

ExWebRTC Endpoint uses [`membrane_telemetry_metrics`](https://github.com/membraneframework/membrane_telemetry_metrics) to aggregate data about media streams and generate reports about them.
To enable metrics aggregation, you have to put line 

```elixir
config :membrane_telemetry_metrics, enabled: true
```

in your config file, add `telemetry_label` to your endpoint configuration

```elixir
%Endpoint.ExWebRTC{
  telemetry_label: [room_id: room_id]
}
```

and start `Membrane.TelemetryMetrics.Reporter` with RTC Engine metrics by calling

```elixir 
{:ok, reporter} = Membrane.TelemetryMetrics.Reporter.start_link(Membrane.RTC.Engine.Endpoint.ExWebRTC.Metrics.metrics())
```

Then, if you want to get a report with metrics values for every running RTC Engine on the node, you have to call
```elixir
Membrane.TelemetryMetrics.Reporter.scrape(reporter)
```

There is a report example below, with only one room with one endpoint inside
```elixir
%{
  {:room_id, "test"} => %{
    {:endpoint_id, "7eda6931-0313-497e-93a0-6a9540407f77"} => %{
      {:track_id,
       "7eda6931-0313-497e-93a0-6a9540407f77:3d228c10-d3b9-4009-b14f-4b0f2b89f7ba:l"} => %{
        "track.metadata": %{"active" => true, "type" => "camera"}
      },
      {:track_id,
       "7eda6931-0313-497e-93a0-6a9540407f77:3d228c10-d3b9-4009-b14f-4b0f2b89f7ba:m"} => %{
        "track.metadata": %{"active" => true, "type" => "camera"}
      },
      {:track_id,
       "7eda6931-0313-497e-93a0-6a9540407f77:90ce43b1-d37a-452e-8a04-b2883e7d54dc:"} => %{
        "track.metadata": %{"active" => true, "type" => "audio"}
      }
    }
  }
}
```
