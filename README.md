## lua-resty-kafka-lab

Benchmark and compatibility testing lab for [lua-resty-kafka](https://github.com/doujiang24/lua-resty-kafka) with KRaft Kafka 4.0+ support.

### Overview

This repo contains:
- 🚀 Load testing setup using OpenResty + BZT/JMeter
- 🔬 Compatibility matrix testing across Kafka versions
- 📊 Benchmark results and compatibility matrix

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
    ./scripts/setup_openresty.sh --openresty-ip 10.0.1.1 --broker-ip 10.0.1.1 --domain resty-kafka.loadtest.rnd

#### JMeter Server
    ./scripts/setup_jmeter.sh --openresty-ip 10.0.1.1 --domain resty-kafka.loadtest.rnd

> Always use private network IP, never 127.0.0.1
> This is required because Kafka Docker containers advertise listeners
> using the host private IP and must be reachable from both
> OpenResty and JMeter servers.

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

### Compatibility Matrix

See [results/compatibility_matrix.md](results/compatibility_matrix.md)

### Benchmark Results

See [results/benchmark_results.md](results/benchmark_results.md)

