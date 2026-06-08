## JMeter Load Testing Guide

### Test Environment

#### Hardware (Hetzner CPX32)
- vCPU: 4
- RAM: 8GB
- Network: Hetzner private network

#### Important Note
Both OpenResty+Kafka server and JMeter server were running on
identical Hetzner CPX32 instances connected via private network.
Kafka and OpenResty share the same server.

### Quick Start

    ./scripts/setup_jmeter.sh --openresty-server-private-ip 10.0.1.1

With custom domain:

    ./scripts/setup_jmeter.sh --openresty-server-private-ip 10.0.1.1 --domain your-custom.domain

### What setup script installs

| Software | Version | Location |
|----------|---------|----------|
| Java | OpenJDK 17 | system |
| BZT | latest | /opt/bzt-venv |

### System Tuning

Script automatically applies the following optimizations:

#### Open Files Limit (/etc/security/limits.conf)
    * soft nofile 65535
    * hard nofile 65535
    root soft nofile 65535
    root hard nofile 65535

#### Network Tuning (/etc/sysctl.conf)
    net.ipv4.ip_local_port_range = 1024 65535
    net.ipv4.tcp_tw_reuse = 1
    net.ipv4.tcp_fin_timeout = 15
    net.core.somaxconn = 65535
    net.ipv4.tcp_max_syn_backlog = 65535
    net.core.rmem_max = 16777216
    net.core.wmem_max = 16777216


### Running Tests

All tests run from /opt/bzt-test directory:

    cd /opt/bzt-test

#### Async Test
    ## Recommended: 200 concurrency for 4vCPU/8GB server
    bzt config.yml loadtest-async.yml -o settings.env.CONCURRENCY=200

#### Sync Test
    ## Recommended: 100 concurrency for 4vCPU/8GB server
    bzt config.yml loadtest-sync.yml -o settings.env.CONCURRENCY=100

#### Payload Size Tests
    bzt config.yml loadtest-sync-1kb.yml -o settings.env.CONCURRENCY=100
    bzt config.yml loadtest-sync-10kb.yml -o settings.env.CONCURRENCY=100
    bzt config.yml loadtest-sync-100kb.yml -o settings.env.CONCURRENCY=100

#### Override Duration
    bzt config.yml loadtest-async.yml \
        -o settings.env.CONCURRENCY=200 \
        -o settings.env.DURATION=10m

### Test Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| CONCURRENCY | 10 | Number of concurrent threads |
| DURATION | 5m | Test duration |
| RAMP_UP | 30s | Ramp up time |
| SYNC_ENDPOINT | /kafka/sync | Sync endpoint |
| ASYNC_ENDPOINT | /kafka/async | Async endpoint |

### Recommended Concurrency (4vCPU/8GB)

| Test | Concurrency | Notes |
|------|-------------|-------|
| Async | 200 | More than 200 shows no improvement |
| Sync | 100 | Higher values increase error rate |
| Sync 1KB | 100 | No degradation vs small payload |
| Sync 10KB | 100 | Minimal degradation |
| Sync 100KB | 100 | FFI CRC32C benefit visible |

### Verifying Zero Data Loss (Async)

After async test compare BZT hits vs Kafka offset:

    ## Get total messages in Kafka topic
    docker exec test-kafka-kraft /opt/kafka/bin/kafka-get-offsets.sh \
        --bootstrap-server kafka-kraft:29093 \
        --topic test-topic

Compare with BZT final-stats output. Numbers should match exactly.

### Troubleshooting

#### Too many open files
    ulimit -n 65535

#### Port exhaustion
    sysctl net.ipv4.ip_local_port_range

Should show: 1024 65535


