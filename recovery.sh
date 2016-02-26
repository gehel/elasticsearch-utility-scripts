#!/usr/bin/env bash
# Monitor an Elasticsearch cluster shard recovery progress
#
# Typical usage: watch ./recovery.sh
#
# Copyright (c) 2016 Bryan Davis, Wikimedia Foundation, and contributors
# Released under the MIT license -- https://opensource.org/licenses/MIT

curl -s '127.0.0.1:9200/_cat/recovery?active_only=true' |
awk '{printf "%-19s %6s %-12s => %-12s\n", $1, $13, $6, $7}' |
sort -n -k2 -r

# vim:sw=4:ts=4:sts=4:et:ft=sh:
