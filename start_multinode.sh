#!/bin/bash

set -eux

docker compose down || true

docker compose up -d

# Test to see if Couchbase Server is up
# Each retry min wait 5s, max 10s. Retry 20 times with exponential backoff (delay 0), fail at 120s
curl --retry-all-errors --connect-timeout 5 --max-time 10 --retry 20 --retry-delay 0 --retry-max-time 120 'http://127.0.0.1:8091'

# Set up CBS
curl -u Administrator:password -v -X POST http://127.0.0.1:8091/nodes/self/controller/settings -d 'path=%2Fopt%2Fcouchbase%2Fvar%2Flib%2Fcouchbase%2Fdata&' -d 'index_path=%2Fopt%2Fcouchbase%2Fvar%2Flib%2Fcouchbase%2Fdata&' -d 'cbas_path=%2Fopt%2Fcouchbase%2Fvar%2Flib%2Fcouchbase%2Fdata&' -d 'eventing_path=%2Fopt%2Fcouchbase%2Fvar%2Flib%2Fcouchbase%2Fdata&'
curl -u Administrator:password -v -X POST http://127.0.0.1:8091/node/controller/setupServices -d 'services=kv%2Cn1ql%2Cindex'
curl -u Administrator:password -v -X POST http://127.0.0.1:8091/pools/default -d 'memoryQuota=3072' -d 'indexMemoryQuota=3072' -d 'ftsMemoryQuota=256'
curl -u Administrator:password -v -X POST http://127.0.0.1:8091/settings/web -d 'password=password&username=Administrator&port=SAME'
curl -u Administrator:password -v -X POST http://localhost:8091/settings/indexes -d indexerThreads=4 -d logLevel=verbose -d maxRollbackPoints=10 \
    -d storageMode=plasma -d memorySnapshotInterval=150 -d stableSnapshotInterval=40000

CLI_ARGS="-c couchbase://cbs -u Administrator -p password"
docker exec cbs-replica1 couchbase-cli node-init $CLI_ARGS
docker exec cbs-replica2 couchbase-cli node-init $CLI_ARGS
REPLICA1_IP=$(docker inspect --format '{{json .NetworkSettings.Networks}}' cbs-replica1 | jq -r 'first(.[]) | .IPAddress')
REPLICA2_IP=$(docker inspect --format '{{json .NetworkSettings.Networks}}' cbs-replica2 | jq -r 'first(.[]) | .IPAddress')
docker exec cbs couchbase-cli server-add $CLI_ARGS --server-add $REPLICA2_IP --server-add-username Administrator --server-add-password password --services data,index,query
docker exec cbs couchbase-cli server-add $CLI_ARGS --server-add $REPLICA1_IP --server-add-username Administrator --server-add-password password --services index,query
docker exec cbs couchbase-cli rebalance $CLI_ARGS
