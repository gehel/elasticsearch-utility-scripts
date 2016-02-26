#!/usr/bin/env bash
# Upgrade an Elasticsearch cluster node safely
#
# This is more of a recipe for doing an upgrade than a set system. The
# important parts are disabling allocation, ensuring that shards are flushed
# and waiting for recovery/stability at each important step.
#
# Jump down to the '## Recipe ##' marker to see the current recipe and
# add/tweak steps.
#
# Copyright (c) 2016 Bryan Davis, Wikimedia Foundation, and contributors
# Released under the MIT license -- https://opensource.org/licenses/MIT

# Bail if something fails
set -e

disable_puppet() {
  echo "Disabling Puppet"
  sudo puppet agent --disable "Upgrading elasticsearch $(date +%Y-%m-%dT%H:%m)"
}

disable_shard_allocation() {
    echo "Stopping shard reallocation"
    curl -s -XPUT 127.0.0.1:9200/_cluster/settings?pretty -d '{
        "transient" : {
            "cluster.routing.allocation.enable": "primaries"
        }
    }'
}

flush_markers() {
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-synced-flush.html
    # "It is harmless to request a synced flush while there is ongoing
    # indexing. Shards that are idle will succeed and shards that are not will
    # fail. Any shards that succeeded will have faster recovery times."
    echo "Flushing sync markers"
    curl -s -XPOST '127.0.0.1:9200/_flush/synced?pretty'
}

stop_elasticsearch() {
    echo "Stopping elasticsearch"
    sudo service elasticsearch stop
}

##
# Upgrade Elasticsearch package
#
# Upgrade is done either via dpkg install of a package on local disk or via
# apt repo. Pass a path to a package to install from local disk. If no
# explicit package is provided then the update will proceed by refreshing the
# apt cache and installing the lastest version that it provides
##
upgrade_elasticsearch() {
    if [[ -n "$1" ]]; then
        echo "Upgrading elasticsearch from $1"
        sudo dpkg -i --force-confdef --force-confold "$1"
    else
        echo "Upgrading elasticsearch from apt"
        sudo /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get update
        sudo /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get \
            -o Dpkg::Options::='--force-confdef' \
            -o Dpkg::Options::='--force-confold' \
            -o Dpkg::Options::='--force-unsafe-io' \
            install --fix-broken --auto-remove --yes elasticsearch
    fi
    builtin hash systemctl &>/dev/null && sudo systemctl daemon-reload
}

start_elasticsearch() {
    echo -n "Starting elasticsearch"
    sudo service elasticsearch start
    until curl -s 127.0.0.1:9200/_cat/health; do
        echo -n '.'
        sleep 1
    done
    echo
}

enable_shard_allocation() {
    curl -s -XPUT 127.0.0.1:9200/_cluster/settings?pretty -d '{
        "transient" : {
            "cluster.routing.allocation.enable": "all"
        }
    }'
}

wait_for_cluster_recovery() {
    local health="/tmp/$(basename $0).$$.tmp"
    until curl -s 127.0.0.1:9200/_cat/health | tee "$health" | grep green; do
        cat "$health"
        sleep 1
    done
}

enable_puppet() {
    sudo puppet agent --enable
}

## Recipe ##
disable_puppet
disable_shard_allocation
flush_markers
stop_elasticsearch
upgrade_elasticsearch

# -- BEGIN optional steps for this particular update --
: <<'__BLOCK_COMMENT'
## Here's an example from when we were adding ferm rules to the nodes
# Apply ferm puppet changes
sudo puppet agent --enable
sudo puppet agent --test --verbose
# Add default drop logging to look for missed firewall config
sudo iptables -N LOGGING
sudo iptables -A INPUT -j LOGGING
sudo iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "iptables-dropped: " --log-level 4
sudo iptables -A LOGGING -j DROP
__BLOCK_COMMENT
# -- END optional steps for this particular update --

start_elasticsearch
enable_shard_allocation
wait_for_cluster_recovery
enable_puppet

# vim:sw=4:ts=4:sts=4:et:ft=sh:
