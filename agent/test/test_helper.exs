Code.require_file("test/support/test_source.ex", "../engine")
Code.require_file("test/support/fake_source_endpoint.ex", "../engine")

ExUnit.start(capture_log: true, exclude: [:skip])
