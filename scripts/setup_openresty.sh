##!/bin/bash
## setup_openresty.sh
## Sets up OpenResty + Kafka environment for lua-resty-kafka-lab
## Run on OpenResty server

set -e

## ==========================================
## Default values
## ==========================================
DOMAIN="resty-kafka.loadtest.rnd"
LIB="patched"
KAFKA="kraft"
TOPIC="test-topic"
SYNC_POOL_SIZE=5
SYNC_LOCK_TIMEOUT=30
ASYNC_BATCH_NUM=5000
ASYNC_FLUSH_TIME=2000
OPENRESTY_IP=""

## ==========================================
## Parse arguments
## ==========================================
while [[ "$##" -gt 0 ]]; do
    case $1 in
        --openresty-server-private-ip) OPENRESTY_IP="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        --lib) LIB="$2"; shift ;;
        --kafka) KAFKA="$2"; shift ;;
        --topic) TOPIC="$2"; shift ;;
        --sync-pool-size) SYNC_POOL_SIZE="$2"; shift ;;
        --sync-lock-timeout) SYNC_LOCK_TIMEOUT="$2"; shift ;;
        --async-batch-num) ASYNC_BATCH_NUM="$2"; shift ;;
        --async-flush-time) ASYNC_FLUSH_TIME="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

## ==========================================
## Validate required parameters
## ==========================================
if [ -z "$OPENRESTY_IP" ]; then
    echo "ERROR: --openresty-server-private-ip is required"
    echo "Usage: ./setup_openresty.sh --openresty-server-private-ip 10.0.1.1"
    exit 1
fi

## ==========================================
## Set broker port based on kafka type
## ==========================================
if [ "$KAFKA" == "kraft" ]; then
    BROKER_PORT=9093
elif [ "$KAFKA" == "zk" ]; then
    BROKER_PORT=9092
else
    echo "ERROR: --kafka must be kraft or zk"
    exit 1
fi

## ==========================================
## Set lua_package_path based on lib
## ==========================================
if [ "$LIB" == "patched" ]; then
    LUA_PACKAGE_PATH="/usr/local/openresty/lualib/lua-resty-kafka-patched/lib/?.lua;;"
elif [ "$LIB" == "original" ]; then
    LUA_PACKAGE_PATH="/usr/local/openresty/lualib/lua-resty-kafka/lib/?.lua;;"
else
    echo "ERROR: --lib must be patched or original"
    exit 1
fi

echo "======================================="
echo "lua-resty-kafka-lab OpenResty Setup"
echo "======================================="
echo "IP:                $OPENRESTY_IP"
echo "Domain:            $DOMAIN"
echo "Lib:               $LIB"
echo "Kafka:             $KAFKA"
echo "Broker port:       $BROKER_PORT"
echo "Topic:             $TOPIC"
echo "Sync pool size:    $SYNC_POOL_SIZE"
echo "Sync lock timeout: $SYNC_LOCK_TIMEOUT"
echo "Async batch num:   $ASYNC_BATCH_NUM"
echo "Async flush time:  $ASYNC_FLUSH_TIME"
echo "======================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

## ==========================================
## Install Docker if not present
## ==========================================
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

## ==========================================
## Clone kafka libraries if not present
## ==========================================
mkdir -p /usr/local/openresty/lualib

if [ ! -d "/usr/local/openresty/lualib/lua-resty-kafka" ]; then
    echo "Cloning original lua-resty-kafka..."
    git clone https://github.com/doujiang24/lua-resty-kafka.git \
        /usr/local/openresty/lualib/lua-resty-kafka
fi

if [ ! -d "/usr/local/openresty/lualib/lua-resty-kafka-patched" ]; then
    echo "Cloning patched lua-resty-kafka..."
    git clone https://github.com/sasa82/lua-resty-kafka.git \
        /usr/local/openresty/lualib/lua-resty-kafka-patched
fi

## ==========================================
## Copy configs to OpenResty
## ==========================================
echo "Copying nginx configs..."
cp "$REPO_DIR/openresty/nginx/conf/nginx.conf" \
    /usr/local/openresty/nginx/conf/nginx.conf

mkdir -p /usr/local/openresty/nginx/conf/conf.d
cp "$REPO_DIR/openresty/nginx/conf/conf.d/kafka-loadtest.conf" \
    /usr/local/openresty/nginx/conf/conf.d/kafka-loadtest.conf

mkdir -p /usr/local/openresty/luaconfigs
cp "$REPO_DIR/openresty/luaconfigs/init.lua" \
    /usr/local/openresty/luaconfigs/init.lua
cp "$REPO_DIR/openresty/luaconfigs/producer_sync.lua" \
    /usr/local/openresty/luaconfigs/producer_sync.lua
cp "$REPO_DIR/openresty/luaconfigs/producer_async.lua" \
    /usr/local/openresty/luaconfigs/producer_async.lua

mkdir -p /usr/local/openresty/lualib/lua-resty-kafka-lab/lib
cp "$REPO_DIR/lib/kafka_producers.lua" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua

## ==========================================
## Replace placeholders in configs
## ==========================================
echo "Configuring placeholders..."

## nginx.conf
sed -i "s|LUA_PACKAGE_PATH|$LUA_PACKAGE_PATH|g" \
    /usr/local/openresty/nginx/conf/nginx.conf

## kafka-loadtest.conf
sed -i "s|DOMAIN_NAME|$DOMAIN|g" \
    /usr/local/openresty/nginx/conf/conf.d/kafka-loadtest.conf
sed -i "s|KAFKA_TOPIC|$TOPIC|g" \
    /usr/local/openresty/nginx/conf/conf.d/kafka-loadtest.conf

## kafka_producers.lua
sed -i "s|BROKER_IP|$OPENRESTY_IP|g" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua
sed -i "s|BROKER_PORT|$BROKER_PORT|g" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua
sed -i "s|SYNC_POOL_SIZE|$SYNC_POOL_SIZE|g" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua
sed -i "s|SYNC_LOCK_TIMEOUT|$SYNC_LOCK_TIMEOUT|g" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua
sed -i "s|ASYNC_BATCH_NUM|$ASYNC_BATCH_NUM|g" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua
sed -i "s|ASYNC_FLUSH_TIME|$ASYNC_FLUSH_TIME|g" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua

## compatibility_test.sh
sed -i "s|DOMAIN_NAME|$DOMAIN|g" \
    "$REPO_DIR/scripts/compatibility_test.sh"

## ==========================================
## Add domain to /etc/hosts
## ==========================================
echo "Adding domain to /etc/hosts..."
if grep -q "$DOMAIN" /etc/hosts; then
    sed -i "/$DOMAIN/d" /etc/hosts
fi
echo "$OPENRESTY_IP $DOMAIN" >> /etc/hosts

## ==========================================
## Start Kafka via Docker Compose
## ==========================================
echo "Starting Kafka..."
COMPOSE_FILE="$REPO_DIR/docker/docker-compose.yml"

## Backup and replace BROKER_IP in docker-compose.yml
cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak"
sed -i "s|BROKER_IP|$OPENRESTY_IP|g" "$COMPOSE_FILE"

if [ "$KAFKA" == "kraft" ]; then
    docker compose -f "$COMPOSE_FILE" up -d kafka-kraft
    echo "Waiting for KRaft Kafka to start..."
    sleep 15
elif [ "$KAFKA" == "zk" ]; then
    docker compose -f "$COMPOSE_FILE" up -d zookeeper kafka-zk
    echo "Waiting for ZooKeeper + Kafka to start..."
    sleep 20
fi

## ==========================================
## Create Kafka topic
## ==========================================
echo "Creating Kafka topic: $TOPIC..."
if [ "$KAFKA" == "kraft" ]; then
    docker exec test-kafka-kraft /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server kafka-kraft:29093 \
        --create \
        --topic "$TOPIC" \
        --partitions 1 \
        --replication-factor 1 \
        --if-not-exists
elif [ "$KAFKA" == "zk" ]; then
    docker exec test-kafka-zookeeper kafka-topics \
        --bootstrap-server kafka-zk:29092 \
        --create \
        --topic "$TOPIC" \
        --partitions 1 \
        --replication-factor 1 \
        --if-not-exists
fi

## ==========================================
## Reload OpenResty
## ==========================================
echo "Reloading OpenResty..."
openresty -s reload

echo ""
echo "======================================="
echo "Setup complete!"
echo "======================================="
echo "Test endpoints:"
echo "  Sync:  http://$DOMAIN/kafka/sync"
echo "  Async: http://$DOMAIN/kafka/async"
echo ""
echo "To run compatibility tests:"
echo "  ./scripts/compatibility_test.sh"
echo "======================================="

