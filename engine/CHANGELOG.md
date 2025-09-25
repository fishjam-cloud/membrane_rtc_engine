# Changelog

## 0.25.0-dev
* Update README [#51](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/51)
* Fix race condition in crash group handling [#55](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/55)
* Allow `Subscriber` to filter based on track types [#65](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/65)
* TestSinkEndpoint requests track variant when track added [#68](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/68)
* Enable `Subscriber` to subscribe to specific tracks [#71](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/71)

## 0.24.0
* Add ex_webrtc integration test [#409](https://github.com/fishjam-dev/membrane_rtc_engine/pull/409)
* Return updated track upon subscription [#3](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/3)
* Use yarn for both webrtc integration tests [#8](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/8)
* Split ex_webrtc integration tests to JSON and protobuf [#13](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/13)
* Send all endpoints metadata on ready notification [#14](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/14)
* Rename `encoding` to `variant` when refering to simulcast layers [#15](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/15)
* Use :protobuf as serializer in tests [#30](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/30)
* Remove PeerConnection Supervisor [#32](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/32)  
* Update membrane core [#45](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/45)
* Update membrane rtp plugins [#46](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/46)

## 0.23.0
* Add RTCP sender reports [#393](https://github.com/fishjam-dev/membrane_rtc_engine/pull/393)
* Add reason to `TrackVariantPaused` event [#392](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/392)
* Lower log level for some logs [#401](https://github.com/fishjam-dev/membrane_rtc_engine/pull/401)
* Add async subscribe [#407](https://github.com/fishjam-dev/membrane_rtc_engine/pull/407)
* Fix RC occuring in add/remove_endpoint [#2](https://github.com/fishjam-cloud/membrane_rtc_engine/pull/2)

## 0.22.0
* Update deps [#374](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/374)
* Fix READMEs [#365](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/365)
* Send reason when endpoint crashes. [#368](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/368)
* Engine doesn't crash after handling `:subscribe` message from removed endpoint and updated `Engine.subscribe` [#381](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/381)
* Add manual and auto subscribe mode. [#383](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/383)

## 0.21.0
* Rename the function `is_simulcast` to `simulcast?` in order to be compliant with elixir style guide. [#349](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/349)
* Engine shouldn't raise when requesting incorrect simulcast variant [#351](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/351)
* Fix multiple RCs when removing tracks quickly [#358](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/358)
* Add option `wait_for_keyframe_request?` to static track sender [#357](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/357)

## 0.20.0
* Add finished notification and remove code related to OpenTelemetry [#340](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/340)
* Notify on endpoint and track metadata updates [#354](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/354)
* Add handling `:track_encoding_enabled` and `:track_encoding_disabled` notification from endpoints [#352](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/352)

## 0.19.0
* Discard messages from endpoints that are not marked as ready [#339](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/339)
* Extend Engine.terminate API [#337](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/337)
* Update to Membrane Core 1.0 [#331](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/331)
* Add `get_tracks` function in `Engine` module [#328](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/328)
* Change some logs to debug [#327](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/327)
* Miniscule doc fix [#333](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/333)

## 0.18.0
* Modify `Track`, mix.exs and docs because of adding File Endpoint [#323](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/323)

## 0.17.1
* Bump deps [#318](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/318)
* Add `get_active_tracks` function in `Endpoint` module [#317](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/317)

## 0.17.0
* Cleanup RTC Engine deps. Move metrics to the WebRTC Endpoint [#306](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/306)
* Add `get_num_forwarded_tracks` function [#300](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/300)
* Add new endpoint and track notifications [#310](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/310)
* Update upgrading guide to use new repo paths [#311](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/311)

## 0.16.0
* Convert RTC Engine into monorepo [#298](https://github.com/jellyfish-dev/membrane_rtc_engine/pull/298)
