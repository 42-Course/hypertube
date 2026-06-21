#!/bin/zsh
# Manual dev shortcut for probing the range client with a preset magnet.
# It depends on external torrent availability and is not a deterministic test.
RANGE_SERVER_PORT=7001 ruby scripts/range_client.rb "magnet:?xt=urn:btih:e7af38e082b8c7ea47b18a3fc7697f166481244b&dn=%5BToonsHub%5D%20Dr%20STONE%20S04E36%201080p%20NF%20WEB-DL%20AAC2.0%20H.264%20%28Multi-Subs%29&tr=http%3A%2F%2Fnyaa.tracker.wf%3A7777%2Fannounce&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce&tr=udp%3A%2F%2Fexodus.desync.com%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce"
