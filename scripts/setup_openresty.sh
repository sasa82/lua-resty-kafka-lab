#!/bin/bash
# setup_openresty.sh
# Sets up OpenResty + Kafka environment for lua-resty-kafka-lab
# Run on OpenResty server

set -e

# ==========================================
# Default values
# ==========================================
DOMAIN="resty-kafka.loadtest.rnd"
LIB="patched"
KAFKA="kraft"
TOPIC="test-topic"
SYNC_POOL_SIZE=5
SYNC_LOCK_TIMEOUT=30
ASYNC_BATCH_NUM=5000
ASYNC_FLUSH_TIME=2000
OPENRESTY_IP=""

# ==========================================
# Parse arguments
# ==========================================
while [ "$#" -gt 0 ]; do
    case "$1" in
        --openresty-server-private-ip) OPENRESTY_IP="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --lib) LIB="$2"; shift 2 ;;
        --kafka) KAFKA="$2"; shift 2 ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --sync-pool-size) SYNC_POOL_SIZE="$2"; shift 2 ;;
        --sync-lock-timeout) SYNC_LOCK_TIMEOUT="$2"; shift 2 ;;
        --async-batch-num) ASYNC_BATCH_NUM="$2"; shift 2 ;;
        --async-flush-time) ASYNC_FLUSH_TIME="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

# ==========================================
# Validate required parameters
# ==========================================
if [ -z "$OPENRESTY_IP" ]; then
    echo "ERROR: --openresty-server-private-ip is required"
    echo "Usage: ./setup_openresty.sh --openresty-server-private-ip 10.0.1.1"
    exit 1
fi

# ==========================================
# Set broker port based on kafka type
# ==========================================
if [ "$KAFKA" == "kraft" ]; then
    BROKER_PORT=9093
elif [ "$KAFKA" == "zk" ]; then
    BROKER_PORT=9092
else
    echo "ERROR: --kafka must be kraft or zk"
    exit 1
fi

# ==========================================
# Set lib paths based on lib parameter
# ==========================================
if [ "$LIB" == "patched" ]; then
    KAFKA_LIB="lua-resty-kafka-patched"
elif [ "$LIB" == "original" ]; then
    KAFKA_LIB="lua-resty-kafka"
else
    echo "ERROR: --lib must be patched or original"
    exit 1
fi

# ==========================================
# Check/Install OpenResty
# ==========================================
if command -v openresty &> /dev/null; then
    OPENRESTY_DIR=$(openresty -V 2>&1 | grep -o '\-\-prefix=[^ ]*' | cut -d= -f2 | xargs dirname)
    echo "OpenResty found at: $OPENRESTY_DIR"
else
    echo "OpenResty not found, installing..."
    apt-get update
    apt-get install -y lsb-release

    wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
    echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/openresty.list
    apt-get update
    apt-get install -y openresty
    
    OPENRESTY_DIR=$(openresty -V 2>&1 | grep -o '\-\-prefix=[^ ]*' | cut -d= -f2 | xargs dirname)
    echo "OpenResty installed at: $OPENRESTY_DIR"
fi

# ==========================================
# Install dependencies
# ==========================================
echo "Installing dependencies..."
apt-get install -y \
    e2fsprogs \
    curl \
    git \
    e2fsck-static \
    libext2fs-dev

# ==========================================
# Set lib paths using OPENRESTY_DIR
# ==========================================
KAFKA_LIB_PATH="$OPENRESTY_DIR/lualib/$KAFKA_LIB/lib/?.lua"
LAB_LIB_PATH="$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/?.lua"

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
echo "OpenResty dir:     $OPENRESTY_DIR"
echo "Kafka lib path:    $KAFKA_LIB_PATH"
echo "Lab lib path:      $LAB_LIB_PATH"
echo "======================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ==========================================
# Install Docker if not present
# ==========================================
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# ==========================================
# Clone kafka libraries if not present
# ==========================================
mkdir -p "$OPENRESTY_DIR/lualib"

if [ ! -d "$OPENRESTY_DIR/lualib/lua-resty-kafka" ]; then
    echo "Cloning original lua-resty-kafka..."
    git clone https://github.com/doujiang24/lua-resty-kafka.git \
        "$OPENRESTY_DIR/lualib/lua-resty-kafka"
fi

if [ ! -d "$OPENRESTY_DIR/lualib/lua-resty-kafka-patched" ]; then
    echo "Cloning patched lua-resty-kafka..."
    git clone https://github.com/sasa82/lua-resty-kafka.git \
        "$OPENRESTY_DIR/lualib/lua-resty-kafka-patched"
fi

# ==========================================
# Copy configs to OpenResty
# ==========================================
echo "Copying nginx configs..."
cp "$REPO_DIR/openresty/nginx/conf/nginx.conf" \
    "$OPENRESTY_DIR/nginx/conf/nginx.conf"

mkdir -p "$OPENRESTY_DIR/nginx/conf/conf.d"
cp "$REPO_DIR/openresty/nginx/conf/conf.d/kafka-loadtest.conf" \
    "$OPENRESTY_DIR/nginx/conf/conf.d/kafka-loadtest.conf"

mkdir -p "$OPENRESTY_DIR/luaconfigs"
cp "$REPO_DIR/openresty/luaconfigs/init.lua" \
    "$OPENRESTY_DIR/luaconfigs/init.lua"
cp "$REPO_DIR/openresty/luaconfigs/producer_sync.lua" \
    "$OPENRESTY_DIR/luaconfigs/producer_sync.lua"
cp "$REPO_DIR/openresty/luaconfigs/producer_async.lua" \
    "$OPENRESTY_DIR/luaconfigs/producer_async.lua"

mkdir -p "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib"
cp "$REPO_DIR/lib/kafka_producers.lua" \
    "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua"

# ==========================================
# Replace placeholders in configs
# ==========================================
echo "Configuring placeholders..."

# nginx.conf
sed -i "s|KAFKA_LIB_PATH|$KAFKA_LIB_PATH|g" \
    "$OPENRESTY_DIR/nginx/conf/nginx.conf"
sed -i "s|LAB_LIB_PATH|$LAB_LIB_PATH|g" \
    "$OPENRESTY_DIR/nginx/conf/nginx.conf"
sed -i "s|OPENRESTY_DIR|$OPENRESTY_DIR|g" \
    "$OPENRESTY_DIR/nginx/conf/nginx.conf"

# kafka-loadtest.conf
sed -i "s|DOMAIN_NAME|$DOMAIN|g" \
    "$OPENRESTY_DIR/nginx/conf/conf.d/kafka-loadtest.conf"
sed -i "s|KAFKA_TOPIC|$TOPIC|g" \
    "$OPENRESTY_DIR/nginx/conf/conf.d/kafka-loadtest.conf"
sed -i "s|OPENRESTY_DIR|$OPENRESTY_DIR|g" \
    "$OPENRESTY_DIR/nginx/conf/conf.d/kafka-loadtest.conf"

# kafka_producers.lua
sed -i "s|BROKER_IP|$OPENRESTY_IP|g" \
    "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua"
sed -i "s|BROKER_PORT|$BROKER_PORT|g" \
    "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua"
sed -i "s|SYNC_POOL_SIZE|$SYNC_POOL_SIZE|g" \
    "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua"
sed -i "s|SYNC_LOCK_TIMEOUT|$SYNC_LOCK_TIMEOUT|g" \
    "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua"
sed -i "s|ASYNC_BATCH_NUM|$ASYNC_BATCH_NUM|g" \
    "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua"
sed -i "s|ASYNC_FLUSH_TIME|$ASYNC_FLUSH_TIME|g" \
    "$OPENRESTY_DIR/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua"

# compatibility_test.sh
sed -i "s|DOMAIN_NAME|$DOMAIN|g" \
    "$REPO_DIR/scripts/compatibility_test.sh"

# ==========================================
# Add domain to /etc/hosts
# ==========================================
echo "Adding domain to /etc/hosts..."
if grep -q "$DOMAIN" /etc/hosts; then
    sed -i "/$DOMAIN/d" /etc/hosts
fi
echo "$OPENRESTY_IP $DOMAIN" >> /etc/hosts

# ==========================================
# Start Kafka via Docker Compose
# ==========================================
echo "Starting Kafka..."
COMPOSE_FILE="$REPO_DIR/docker/docker-compose.yml"

# Backup and replace BROKER_IP in docker-compose.yml
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

# ==========================================
# Create Kafka topic
# ==========================================
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

# ==========================================
# Reload OpenResty
# ==========================================
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

