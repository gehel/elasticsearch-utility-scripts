#!/usr/bin/env bash
set -e

es_server_prefix=elastic20
es_server_suffix=.codfw.wmnet
first_server_index=4
nb_of_servers_in_cluster=24

for i in $(seq -w ${first_server_index} ${nb_of_servers_in_cluster}); do
  servers="${servers} ${es_server_prefix}${i}${es_server_suffix}"
done

for server in ${servers}; do
    echo ready to start upgrade of ${server}
    echo make sure icinga alerts are disabled for ${server}
    echo please log the action to \#wikimedia-operations
    echo [ENTER] to continue, [CTRL]-[C] to stop
    read

    command_file=$(ssh ${server} tempfile --prefix cmd- --suffix -elastic-upgrade.sh)

    echo uploading command file: ${command_file}
    scp upgrade-es.sh ${server}:${command_file}

    echo running command file
    ssh ${server} bash ${command_file}

    echo cleanup
    ssh ${server} rm ${command_file}

    echo ${server} upgraded, please test
    echo re-enable icinga alerts for ${server}
    echo [ENTER] to continue, [CTRL]-[C] to stop
    read
    echo Done for ${server}
    echo ==============================================
done
