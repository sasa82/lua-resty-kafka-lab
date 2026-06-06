## lua-resty-kafka-lab

Benchmark and compatibility testing lab for [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) with KRaft Kafka 4.0+ support.

### Overview

This repo contains:
- 🚀 Load testing setup using OpenResty + BZT/JMeter
- 🔬 Compatibility matrix testing across Kafka versions
- 📊 Benchmark results and compatibility matrix

#### About the patched fork
- Original library: [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka)
- Patched fork: [lua-resty-kafka-patched](https://github.com/sasa82/lua-resty-kafka)
- Key improvement: adds Produce API v3+ support enabling KRaft Kafka 4.0+ compatibility
- Zero regressions on all previously supported Kafka versions

### Requirements

#### OpenResty Server
- Ubuntu 20.04+
- OpenResty 1.x
- Docker + Docker Compose
- Private network IP (e.g. 10.0.1.1)

#### JMeter Server
- Ubuntu 20.04+
- Java 11+
- BZT/JMeter

### Quick Start

#### OpenResty Server
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1

#### JMeter Server
    ./scripts/setup_jmeter.sh --openresty-server-private-ip 10.0.1.1

> Always use private network IP of OpenResty server, never 127.0.0.1
> This is required because Kafka Docker containers advertise listeners
> using the host private IP and must be reachable from both
> OpenResty and JMeter servers.

> Default domain: resty-kafka.loadtest.rnd
> To use custom domain:
>     ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --domain your-custom.domain
>     ./scripts/setup_jmeter.sh --openresty-server-private-ip 10.0.1.1 --domain your-custom.domain

> Default lib is patched. Use --lib original to test with original library.
> Default kafka is kraft. Use --kafka zk to test with ZooKeeper.

### Switching Between KRaft and ZooKeeper

The setup script controls which library and broker port to use:

| --lib | --kafka | Port | Description |
|-------|---------|------|-------------|
| patched | kraft | 9093 | Patched lib + KRaft (default) |
| original | zk | 9092 | Original lib + ZooKeeper |

    ## Test with patched lib + KRaft (default)
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib patched --kafka kraft

    ## Test with original lib + ZooKeeper
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib original --kafka zk

Script will automatically:
- Switch lua_package_path to correct library
- Switch broker port (9093 KRaft / 9092 ZooKeeper)
- Reload OpenResty

### Repository Structure

    lua-resty-kafka-lab/
    ├── README.md
    ├── docker/
    │   └── docker-compose.yml
    ├── openresty/
    │   ├── nginx/
    │   │   └── conf/
    │   │       ├── nginx.conf
    │   │       └── conf.d/
    │   │           └── kafka-loadtest.conf
    │   └── luaconfigs/
    │       ├── init.lua
    │       ├── producer_sync.lua
    │       └── producer_async.lua
    ├── lib/
    │   └── kafka_producers.lua
    ├── bzt/
    │   └── *.yml
    ├── scripts/
    │   ├── setup_openresty.sh
    │   ├── setup_jmeter.sh
    │   └── compatibility_test.sh
    └── results/
        ├── compatibility_matrix.md
        └── benchmark_results.md

### Tuning

#### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| --openresty-server-private-ip | required | Private IP of OpenResty server |
| --domain | resty-kafka.loadtest.rnd | Domain name for OpenResty server |
| --lib | patched | Library to use: patched or original |
| --kafka | kraft | Kafka type: kraft or zk |
| --sync-pool-size | 5 | Number of sync producers per worker |
| --sync-lock-timeout | 30 | Lock timeout in seconds |
| --async-batch-num | 5000 | Async batch size |
| --async-flush-time | 2000 | Async flush interval in ms |

#### Full setup command with all options:
    ./scripts/setup_openresty.sh \
        --openresty-server-private-ip 10.0.1.1 \
        --domain resty-kafka.loadtest.rnd \
        --lib patched \
        --kafka kraft \
        --sync-pool-size 5 \
        --sync-lock-timeout 30 \
        --async-batch-num 5000 \
        --async-flush-time 2000

#### LOCK_TIMEOUT
- Higher value = fewer errors under high load, slower failure response
- Lower value = faster failure response, more errors under high load
- Recommended: start with 30s and adjust based on your Kafka latency

#### POOL_SIZE
- More producers = higher throughput for sync mode
- Each worker has its own pool
- Recommended: match to number of Kafka partitions

### Compatibility Matrix

See [results/compatibility_matrix.md](results/compatibility_matrix.md)

### Benchmark Results

See [results/benchmark_results.md](results/benchmark_results.md)
