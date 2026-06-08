#!/bin/bash
# compatibility_test.sh
# Tests lua-resty-kafka compatibility across different Kafka versions
# Run on OpenResty server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

RESULTS_FILE="compatibility_results_$(date +%Y%m%d_%H%M%S).log"
COMPAT_TOPIC="compat-test-topic"
COMPOSE_FILE="$REPO_DIR/docker/docker-compose-compat.yml"
cp "$REPO_DIR/docker/docker-compose.yml" "$COMPOSE_FILE"

# ==========================================
# Default values
# ==========================================
DOMAIN="resty-kafka.loadtest.rnd"
LIB="patched"

# ==========================================
# Parse arguments
# ==========================================
while [ "$#" -gt 0 ]; do
    case "$1" in
        --domain) DOMAIN="$2"; shift 2 ;;
        --lib) LIB="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Confluent Platform to Apache Kafka version mapping:
# 7.0.x -> Kafka 3.0.x
# 7.2.x -> Kafka 3.2.x
# 7.4.x -> Kafka 3.4.x
# 7.5.x -> Kafka 3.5.x
# 7.6.x -> Kafka 3.6.x
ZK_VERSIONS=(
    "7.0.0"
    "7.2.0"
    "7.4.0"
    "7.5.0"
    "7.6.0"
)

KRAFT_VERSIONS=(
    "3.7.0"
    "3.8.0"
    "3.9.0"
    "4.0.0"
    "4.1.0"
    "4.2.0"
)

log() {
    local msg="$1"
    local color="${2:-$NC}"
    echo -e "${color}${msg}${NC}"
    echo "$msg" >> "$RESULTS_FILE"
}

# ==========================================
# Switch kafka config function
# Just changes port in kafka_producers.lua
# and reloads OpenResty - no container mgmt
# ==========================================
switch_kafka_config() {
    local kafka_type="$1"  # zk or kraft

    if [ "$kafka_type" == "zk" ]; then
        PORT=9092
    else
        PORT=9093
    fi

    log "Switching OpenResty to $kafka_type (port $PORT)..." "$YELLOW"

    # Update port in kafka_producers.lua
    sed -i "s|port = [0-9]*|port = $PORT|g" \
        /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua

    # Reload OpenResty
    openresty -s reload
    sleep 2

    log "OpenResty switched to $kafka_type" "$GREEN"
}

log "=======================================" "$YELLOW"
log "Kafka Compatibility Test - $(date)"
log "Library: $LIB"
log "Domain: $DOMAIN"
log "Results file: $RESULTS_FILE"
log "======================================="

# ==========================================
# Save current state before tests
# ==========================================
SAVED_PORT=$(grep "port = " /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua | grep -o 'port = [0-9]*' | grep -o '[0-9]*')
SAVED_TOPIC=$(grep "kafka_topic" /usr/local/openresty/nginx/conf/conf.d/kafka-loadtest.conf | grep -o '"[^"]*"' | tr -d '"' | tail -1)

log "Saving current state..." "$YELLOW"
log "Current port: $SAVED_PORT"
log "Current topic: $SAVED_TOPIC"

test_kafka() {
    local kafka_type="$1"    # zk or kraft
    local version="$2"
    local port="$3"
    local container="$4"
    local bootstrap="$5"

    log ""
    log "---------------------------------------" "$YELLOW"
    log "Testing $kafka_type Kafka version: $version"
    log "---------------------------------------"

    # Update docker compose image version
    if [ "$kafka_type" == "zk" ]; then
        sed -i "s|confluentinc/cp-kafka:.*|confluentinc/cp-kafka:${version}|g" "$COMPOSE_FILE"
    else
        sed -i "s|apache/kafka:.*|apache/kafka:${version}|g" "$COMPOSE_FILE"
    fi

    # Restart containers
    log "Starting Kafka $kafka_type $version..."
    if [ "$kafka_type" == "zk" ]; then
        docker compose -f "$COMPOSE_FILE" up -d zookeeper kafka-zk
        sleep 30  # wait for ZK + Kafka to start
    else
        docker compose -f "$COMPOSE_FILE" up -d kafka-kraft
        sleep 15  # wait for KRaft to start
    fi

    # Check if container is running
    if ! docker ps | grep -q "$container"; then
        log "FAIL: Container $container failed to start" "$RED"
        echo "--- Kafka logs for $kafka_type $version (startup failure) ---" >> "$RESULTS_FILE"
        docker logs "$container" --tail 50 2>&1 >> "$RESULTS_FILE"
        echo "--- End Kafka logs ---" >> "$RESULTS_FILE"
        echo "| $kafka_type | $version | FAIL | FAIL | 0 | FAIL |" >> "$RESULTS_FILE"
        return 1
    fi

    log "Container started, waiting for Kafka to be ready..."
    sleep 10

    # Clear OpenResty error log before each test
    > /usr/local/openresty/nginx/logs/error.log

    # Create compat test topic with 1 partition
    log "Creating compat test topic..."
    if [ "$kafka_type" == "zk" ]; then
        docker exec "$container" kafka-topics \
            --bootstrap-server "$bootstrap" \
            --create \
            --topic "$COMPAT_TOPIC" \
            --partitions 1 \
            --replication-factor 1 \
            --if-not-exists 2>/dev/null
    else
        docker exec "$container" /opt/kafka/bin/kafka-topics.sh \
            --bootstrap-server "$bootstrap" \
            --create \
            --topic "$COMPAT_TOPIC" \
            --partitions 1 \
            --replication-factor 1 \
            --if-not-exists 2>/dev/null
    fi

    sleep 3

    # Update nginx conf to use compat topic
    sed -i "s|set \$kafka_topic \".*\"|set \$kafka_topic \"$COMPAT_TOPIC\"|g" \
        /usr/local/openresty/nginx/conf/conf.d/kafka-loadtest.conf

    # Reload OpenResty to reinitialize producers
    openresty -s reload
    sleep 2

    # Get offset before
    if [ "$kafka_type" == "zk" ]; then
        offset_before=$(docker exec "$container" kafka-get-offsets \
            --bootstrap-server "$bootstrap" \
            --topic "$COMPAT_TOPIC" 2>/dev/null | grep "$COMPAT_TOPIC:0:" | cut -d: -f3)
    else
        offset_before=$(docker exec "$container" /opt/kafka/bin/kafka-get-offsets.sh \
            --bootstrap-server "$bootstrap" \
            --topic "$COMPAT_TOPIC" 2>/dev/null | grep "$COMPAT_TOPIC:0:" | cut -d: -f3)
    fi

    offset_before=${offset_before:-0}
    log "Offset before: $offset_before"

    # Test SYNC
    log "Testing SYNC..."
    sync_response=$(curl -s -X POST "http://$DOMAIN/kafka/sync" \
        -H "Content-Type: application/json" \
        -d '{"source":"compat-test","mode":"sync"}' \
        --max-time 10)

    if echo "$sync_response" | grep -q '"success":true'; then
        log "SYNC curl: OK" "$GREEN"
        sync_curl_result="OK"
    else
        log "SYNC curl: FAIL - $sync_response" "$RED"
        sync_curl_result="FAIL"
    fi

    sleep 2

    # Test ASYNC
    log "Testing ASYNC..."
    async_response=$(curl -s -X POST "http://$DOMAIN/kafka/async" \
        -H "Content-Type: application/json" \
        -d '{"source":"compat-test","mode":"async"}' \
        --max-time 10)

    if echo "$async_response" | grep -q '"success":true'; then
        log "ASYNC curl: OK" "$GREEN"
        async_curl_result="OK"
    else
        log "ASYNC curl: FAIL - $async_response" "$RED"
        async_curl_result="FAIL"
    fi

    sleep 3  # wait for async flush

    # Get offset after
    if [ "$kafka_type" == "zk" ]; then
        offset_after=$(docker exec "$container" kafka-get-offsets \
            --bootstrap-server "$bootstrap" \
            --topic "$COMPAT_TOPIC" 2>/dev/null | grep "$COMPAT_TOPIC:0:" | cut -d: -f3)
    else
        offset_after=$(docker exec "$container" /opt/kafka/bin/kafka-get-offsets.sh \
            --bootstrap-server "$bootstrap" \
            --topic "$COMPAT_TOPIC" 2>/dev/null | grep "$COMPAT_TOPIC:0:" | cut -d: -f3)
    fi

    offset_after=${offset_after:-0}
    log "Offset after: $offset_after"

    offset_diff=$((offset_after - offset_before))
    log "Messages received by Kafka: $offset_diff"

    # Determine overall result
    if [ "$sync_curl_result" == "OK" ] && [ "$async_curl_result" == "OK" ] && [ "$offset_diff" -ge 2 ]; then
        log "RESULT: PASS ✓" "$GREEN"
        overall="PASS"
    else
        log "RESULT: FAIL ✗" "$RED"
        overall="FAIL"

        # Capture Kafka logs on failure
        log "Capturing Kafka logs..." "$YELLOW"
        echo "" >> "$RESULTS_FILE"
        echo "--- Kafka logs for $kafka_type $version ---" >> "$RESULTS_FILE"
        docker logs "$container" --tail 50 2>&1 >> "$RESULTS_FILE"
        echo "--- End Kafka logs ---" >> "$RESULTS_FILE"

        # Capture OpenResty error log on failure
        echo "" >> "$RESULTS_FILE"
        echo "--- OpenResty errors for $kafka_type $version ---" >> "$RESULTS_FILE"
        tail -30 /usr/local/openresty/nginx/logs/error.log >> "$RESULTS_FILE"
        echo "--- End OpenResty errors ---" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    fi

    # Log to results file in table format
    echo "| $kafka_type | $version | $sync_curl_result | $async_curl_result | $offset_diff | $overall |" >> "$RESULTS_FILE"

    # Remove containers and volumes to clean up between versions
    if [ "$kafka_type" == "zk" ]; then
        docker compose -f "$COMPOSE_FILE" rm -f -s -v kafka-zk zookeeper
        docker volume prune -f
    else
        docker compose -f "$COMPOSE_FILE" rm -f -s -v kafka-kraft
        docker volume prune -f
    fi

    sleep 5
}

# Write table header to results file
echo "" >> "$RESULTS_FILE"
echo "| Type | Version | Sync | Async | Messages | Result |" >> "$RESULTS_FILE"
echo "|------|---------|------|-------|----------|--------|" >> "$RESULTS_FILE"

# ==========================================
# Switch to ZooKeeper config
# ==========================================
switch_kafka_config "zk"

# Test ZooKeeper versions
log ""
log "=======================================" "$YELLOW"
log "TESTING ZOOKEEPER KAFKA VERSIONS"
log "Confluent Platform to Apache Kafka version mapping:"
log "7.0.x -> Kafka 3.0.x"
log "7.2.x -> Kafka 3.2.x"
log "7.4.x -> Kafka 3.4.x"
log "7.5.x -> Kafka 3.5.x"
log "7.6.x -> Kafka 3.6.x"
log "======================================="

for version in "${ZK_VERSIONS[@]}"; do
    test_kafka "zk" "$version" "9092" "test-kafka-zookeeper" \
        "kafka-zk:29092"
done

# ==========================================
# Switch to KRaft config
# ==========================================
switch_kafka_config "kraft"

# Test KRaft versions
log ""
log "=======================================" "$YELLOW"
log "TESTING KRAFT KAFKA VERSIONS"
log "======================================="

for version in "${KRAFT_VERSIONS[@]}"; do
    test_kafka "kraft" "$version" "9093" "test-kafka-kraft" \
        "kafka-kraft:29093"
done

log ""
log "=======================================" "$YELLOW"
log "ALL TESTS COMPLETE"
log "Results saved to: $RESULTS_FILE"
log "======================================="

# ==========================================
# Restore original docker-compose
# ==========================================
cp "$COMPOSE_FILE.bak" "$COMPOSE_FILE"
log "docker-compose.yml restored to original" "$GREEN"

# ==========================================
# Restore original state
# ==========================================
log "Restoring original state..." "$YELLOW"

# Restore topic
sed -i "s|set \$kafka_topic \".*\"|set \$kafka_topic \"$SAVED_TOPIC\"|g" \
    /usr/local/openresty/nginx/conf/conf.d/kafka-loadtest.conf

# Restore port
sed -i "s|port = [0-9]*|port = $SAVED_PORT|g" \
    /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/kafka_producers.lua

# Restart both Kafka containers
log "Restarting Kafka containers..." "$YELLOW"
docker compose -f "$COMPOSE_FILE" up -d kafka-kraft zookeeper kafka-zk
sleep 20

## Recreate topics on both Kafka instances
echo "Recreating topics..."
docker exec test-kafka-kraft /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-kraft:29093 \
    --create \
    --topic "$SAVED_TOPIC" \
    --partitions 4 \
    --replication-factor 1 \
    --if-not-exists

docker exec test-kafka-zookeeper kafka-topics \
    --bootstrap-server kafka-zk:29092 \
    --create \
    --topic "$SAVED_TOPIC" \
    --partitions 4 \
    --replication-factor 1 \
    --if-not-exists
# Reload OpenResty
openresty -s reload
#Remove compat script compose file
rm -f "$COMPOSE_FILE"

log ""
log "=======================================" "$GREEN"
log "State restored!" "$GREEN"
log "Port: $SAVED_PORT" "$GREEN"
log "Topic: $SAVED_TOPIC" "$GREEN"
log "=======================================" "$GREEN"

# Print final summary
echo ""
echo "Final Results:"
cat "$RESULTS_FILE" | grep "^|"

