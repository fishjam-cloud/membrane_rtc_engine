Mox.defmock(ExAws.Request.HttpMock, for: ExAws.Request.HttpClient)
Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)

Code.require_file("test/support/whip_server.ex", "../forwarder")

ExUnit.start(capture_log: true, exclude: [:skip])
