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
- Key improvement: adds Produce API v3-v8 support enabling KRaft Kafka 4.0+ compatibility
- Zero regressions on all previously supported Kafka versions

### Why this patch exists

KRaft Kafka 4.0+ requires Produce API v3+ which uses RecordBatch format.
Original library uses API version 1 (MessageSet format) which KRaft 4.0+ rejects:

    UnsupportedVersionException: Received request for api with key 0 (Produce)
    and unsupported version 1

This patched fork fixes this by implementing Produce API v3-v8
with RecordBatch format and CRC32C checksum.

> To reproduce the error use --lib original --kafka kraft
> This is expected behavior and demonstrates why the patch is needed

### Requirements

#### OpenResty Server
- Ubuntu 20.04+
- Private network IP (e.g. 10.0.1.1)
- Minimum 150GB disk space
  (100KB payload test generates ~2GB per minute of Kafka data)

> OpenResty, Docker and all dependencies are installed automatically by setup_openresty.sh

#### Dependencies installed automatically
- `openresty` - nginx based platform for Lua
- `docker` - container runtime for Kafka
- `git` - for cloning kafka libraries
- `curl` - for downloading packages
- `libext2fs-dev` - required for FFI CRC32C acceleration
  - Without it pure Lua CRC32C is used (slower for messages > 50KB)
  - See [results/benchmark_results.md](results/benchmark_results.md) for performance comparison

#### JMeter Server
- Ubuntu 20.04+
- Minimum 100GB disk space

> Java, BZT and all dependencies are installed automatically by setup_jmeter.sh

### Quick Start

> Run all scripts as root:
>     sudo su -
>     cd lua-resty-kafka-lab

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

### Compatibility Testing

Compatibility matrix script tests current library against all Kafka versions automatically.
Must be run on OpenResty server after setup is complete.

#### Prerequisites
- setup_openresty.sh must be run first
- OpenResty must be running

#### Usage

    ## Run on OpenResty server:
    ./scripts/compatibility_test.sh

#### Testing both libraries

Script tests whichever library was configured by setup_openresty.sh.
To get results for both libraries run twice:

    ## Test patched lib (default):
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib patched
    ./scripts/compatibility_test.sh

    ## Test original lib:
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib original --kafka zk
    ./scripts/compatibility_test.sh

#### What it does
- Tests ZooKeeper Kafka versions (Confluent Platform): 7.0.0, 7.2.0, 7.4.0, 7.5.0, 7.6.0 (Kafka < 3.7.x)
- Tests KRaft Kafka versions (Apache Kafka): 3.7.0, 3.8.0, 3.9.0, 4.0.0, 4.1.0, 4.2.0
- Tests both sync and async producers for each version
- Verifies messages actually land in Kafka via offset check
- Captures Kafka and OpenResty logs on failure
- Saves results to timestamped log file
- Automatically restores all settings after completion

#### Results
Results are saved to:
    compatibility_results_YYYYMMDD_HHMMSS.log

See [results/compatibility_matrix.md](results/compatibility_matrix.md) for our test results.

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
    ├── jmeter/
    │   ├── README.md
    │   ├── bzt/
    │   │   ├── config.yml
    │   │   ├── loadtest-sync.yml
    │   │   ├── loadtest-async.yml
    │   │   ├── loadtest-sync-1kb.yml
    │   │   ├── loadtest-sync-10kb.yml
    │   │   ├── loadtest-sync-100kb.yml
    │   │   └── payloads/
    │   │       ├── payload_1kb.txt
    │   │       ├── payload_10kb.txt
    │   │       └── payload_100kb.txt
    ├── scripts/
    │   ├── README.md
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
| --topic | test-topic | Kafka topic name |
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
        --topic test-topic \
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
