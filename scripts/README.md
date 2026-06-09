## Scripts

This directory contains setup and testing scripts for lua-resty-kafka-lab.
All scripts must be run as root on the target server.

    sudo su -
    cd lua-resty-kafka-lab

---

### setup_openresty.sh

Sets up complete OpenResty + Kafka environment on a single server.

#### Usage
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1

#### What it does step by step:
1. Parses and validates arguments
2. Sets broker port based on --kafka parameter (9093 KRaft / 9092 ZK)
3. Sets lua_package_path based on --lib parameter (patched / original)
4. Installs base dependencies (git, curl, e2fsprogs, libext2fs-dev)
5. Installs OpenResty if not present (from openresty.org repository)
6. Applies system tuning (only on fresh install):
   - Increases open files limit to 65535
   - Tunes TCP settings for high load
7. Installs Docker if not present
8. Clones both lua-resty-kafka repos to /usr/local/openresty/lualib/:
   - lua-resty-kafka (original)
   - lua-resty-kafka-patched (patched fork)
9. Copies nginx configs to /usr/local/openresty/nginx/conf/
10. Copies Lua configs to /usr/local/openresty/luaconfigs/
11. Copies kafka_producers.lua to /usr/local/openresty/lualib/lua-resty-kafka-lab/lib/
12. Replaces all placeholders in configs:
    - BROKER_IP -> actual server IP
    - BROKER_PORT -> 9093 or 9092
    - DOMAIN_NAME -> actual domain
    - KAFKA_TOPIC -> actual topic name
    - SYNC_POOL_SIZE, SYNC_LOCK_TIMEOUT
    - ASYNC_BATCH_NUM, ASYNC_FLUSH_TIME
    - LUA_PACKAGE_PATH -> correct lib path
13. Adds domain to /etc/hosts
14. Starts both Kafka containers (KRaft + ZooKeeper)
15. Creates Kafka topic on both instances with 4 partitions
16. Reloads OpenResty

#### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| --openresty-server-private-ip | required | Private IP of server |
| --domain | resty-kafka.loadtest.rnd | Domain name |
| --lib | patched | Library: patched or original |
| --kafka | kraft | Initial Kafka type: kraft or zk |
| --topic | test-topic | Kafka topic name |
| --sync-pool-size | 5 | Sync producers per worker |
| --sync-lock-timeout | 30 | Lock timeout in seconds |
| --async-batch-num | 5000 | Async batch size |
| --async-flush-time | 2000 | Async flush interval ms |

#### Important Notes

> Always use private network IP, never 127.0.0.1

> --lib original with --kafka kraft will produce errors:
>     UnsupportedVersionException: Received request for api with key 0 (Produce)
>     and unsupported version 1
> This is expected - it demonstrates why the patch was created.
> Use --lib original --kafka kraft only to reproduce the issue.

#### Switch between KRaft and ZooKeeper
    ## Switch to ZooKeeper with original lib
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib original --kafka zk

    ## Switch back to KRaft with patched lib (default)
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib patched --kafka kraft

---

### compatibility_test.sh

Tests lua-resty-kafka compatibility across different Kafka versions.
Must be run on OpenResty server after setup_openresty.sh completes.

#### Usage
    ./scripts/compatibility_test.sh

#### Prerequisites
setup_openresty.sh must be run first to:
- Populate broker IP in all configs
- Configure lua library path
- Start Kafka containers
- Create docker-compose.yml with correct IP

#### What it does step by step:
1. Saves current OpenResty state (port, topic)
2. Creates own copy of docker-compose for testing
3. Switches OpenResty to ZooKeeper config (port 9092)
4. Tests each ZooKeeper Kafka version:
   - Updates docker-compose with new Kafka version
   - Starts ZooKeeper + Kafka containers
   - Creates compat-test-topic (1 partition)
   - Updates nginx to use compat-test-topic
   - Tests sync endpoint via curl
   - Tests async endpoint via curl
   - Verifies messages landed in Kafka via offset check
   - Captures Kafka and OpenResty logs on failure
   - Removes containers and volumes between versions
5. Switches OpenResty to KRaft config (port 9093)
6. Tests each KRaft Kafka version (same steps as above)
7. Removes compat docker-compose copy
8. Restores original OpenResty state (port, topic)
9. Restarts both Kafka containers
10. Recreates original topic with 4 partitions
11. Reloads OpenResty

#### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| --domain | resty-kafka.loadtest.rnd | Domain name |

#### Note on library testing
Compatibility script has no --lib parameter.
Library is configured by setup_openresty.sh.

To get results for both libraries run twice:

    ## Test patched lib (default):
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib patched
    ./scripts/compatibility_test.sh

    ## Test original lib:
    ./scripts/setup_openresty.sh --openresty-server-private-ip 10.0.1.1 --lib original --kafka zk
    ./scripts/compatibility_test.sh

#### Versions tested

ZooKeeper (Confluent Platform):
- 7.0.0 (Kafka 3.0.x)
- 7.2.0 (Kafka 3.2.x)
- 7.4.0 (Kafka 3.4.x)
- 7.5.0 (Kafka 3.5.x)
- 7.6.0 (Kafka 3.6.x)

KRaft (Apache Kafka):
- 3.7.0, 3.8.0, 3.9.0
- 4.0.0, 4.1.0, 4.2.0

#### Results
Results saved to timestamped log file:
    compatibility_results_YYYYMMDD_HHMMSS.log

See [results/compatibility_matrix.md](../results/compatibility_matrix.md)

#### Important Notes
> Must be run on OpenResty server (uses local docker and openresty commands)
> Script automatically restores all settings after completion
> Uses separate compat-test-topic to avoid interfering with test-topic
> ZooKeeper kept at stable version (6.0.0), only Kafka version changes

---

### setup_jmeter.sh

Sets up BZT load testing environment on JMeter server.

#### Usage
    ./scripts/setup_jmeter.sh --openresty-server-private-ip 10.0.1.1

#### What it does step by step:
1. Parses and validates arguments
2. Updates system packages
3. Installs base dependencies (git, curl, wget, python3-venv, openjdk-17)
4. Creates BZT virtual environment at /opt/bzt-venv
5. Installs BZT in virtual environment
6. Adds BZT to PATH in ~/.bashrc
7. Applies system tuning for load testing:
   - Increases open files limit to 65535
   - Tunes TCP settings for high concurrency
8. Copies BZT configs to /opt/bzt-test/
9. Generates payload files (1KB, 10KB, 100KB)
10. Replaces DOMAIN_NAME placeholder in config.yml
11. Adds domain to /etc/hosts

#### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| --openresty-server-private-ip | required | Private IP of OpenResty server |
| --domain | resty-kafka.loadtest.rnd | Domain name |

#### Running tests
After setup activate PATH and run tests from /opt/bzt-test:

    source ~/.bashrc
    cd /opt/bzt-test

    ## Async test (recommended: 200 concurrency)
    /opt/bzt-venv/bin/bzt config.yml loadtest-async.yml -o settings.env.CONCURRENCY=200

    ## Sync test (recommended: 100 concurrency)
    /opt/bzt-venv/bin/bzt config.yml loadtest-sync.yml -o settings.env.CONCURRENCY=100

    ## Payload size tests
    /opt/bzt-venv/bin/bzt config.yml loadtest-sync-1kb.yml -o settings.env.CONCURRENCY=100
    /opt/bzt-venv/bin/bzt config.yml loadtest-sync-10kb.yml -o settings.env.CONCURRENCY=100

    ## 100KB test - limit duration to avoid disk space issues
    /opt/bzt-venv/bin/bzt config.yml loadtest-sync-100kb.yml \
        -o settings.env.CONCURRENCY=100 \
        -o settings.env.DURATION=2m \
        -o settings.env.RAMP_UP=10s

#### Important Notes
> BZT manages its own JMeter installation automatically
> JMeter downloaded on first test run to ~/.bzt/
> 100KB test generates ~2GB per minute - monitor disk space!
> Minimum 100GB disk recommended on JMeter server
> System tuning applied automatically by this script
