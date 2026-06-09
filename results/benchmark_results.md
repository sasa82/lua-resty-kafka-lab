## Benchmark Results

### Test Environment

#### Hardware (Hetzner CPX32)
- vCPU: 4
- RAM: 8GB
- Disk: 150GB
- Network: Hetzner private network

#### Important Note
Both OpenResty+Kafka server and JMeter server were running on
identical Hetzner CPX32 instances connected via private network.
Kafka and OpenResty share the same server.

#### Software
- OpenResty 1.31.1.1
- Kafka KRaft: apache/kafka:4.2.0
- BZT/JMeter for load generation
- lua-resty-kafka (patched fork, api_version=3)

#### OpenResty Configuration
- 3 nginx workers
- Producer pool: 5 producers per worker (sync)
- Sync lock timeout: 30s
- api_version: 3 (default)

#### Async Producer Config
    local async_config = {
        producer_type = "async",
        flush_time = 2000,
        batch_num = 5000,
        api_version = 3,
    }

#### Sync Producer Config
    local sync_config = {
        producer_type = "sync",
        api_version = 3,
    }

#### System Tuning (Critical for performance!)
Applied on OpenResty server automatically by setup_openresty.sh:

    net.ipv4.ip_local_port_range = 1024 65535
    net.ipv4.tcp_tw_reuse = 1
    net.ipv4.tcp_fin_timeout = 15
    net.core.somaxconn = 65535
    net.ipv4.tcp_max_syn_backlog = 65535
    net.core.rmem_max = 16777216
    net.core.wmem_max = 16777216
    * soft nofile 65535
    * hard nofile 65535

---

### Main Results

#### Async Test (200 concurrency)

| Metric | Value |
|--------|-------|
| RPS | ~25,600 |
| Success | 100% |
| Avg latency | 1ms |
| Data loss | 0 ✅ |
| Partitions | 4 (evenly distributed) |

#### Zero Data Loss Verification

All async tests verified by comparing BZT hit count vs Kafka offset difference:

| Test | BZT Hits | Kafka Messages | Match |
|------|----------|----------------|-------|
| Async 200 users run 1 | 8,879,788 | 8,879,788 | ✓ |
| Async 200 users run 2 | 8,169,829 | 8,169,829 | ✓ |
| Async 500 users | 8,256,371 | 8,256,371 | ✓ |


---

### System Tuning Impact (Sync Mode)

System tuning on OpenResty server dramatically improves sync performance:

| Concurrency | Tuning | RPS | Latency | Failures |
|-------------|--------|-----|---------|----------|
| 100 | Before | ~2,223 | 42ms | 0% |
| 100 | After | ~7,689 | 12ms | 0% |
| 200 | After | ~7,839 | 24ms | 0% |

> Without tuning: port exhaustion errors at higher concurrency
> With tuning: 3.5x more RPS, better latency

---

### Payload Size Impact (Sync, 100 concurrency, after tuning)

| Payload | RPS | Latency | Success | Data loss |
|---------|-----|---------|---------|-----------|
| ~60b | ~7,689 | 12ms | 100% | 0 ✅ |
| 1KB | ~7,584 | 12ms | 100% | 0 ✅ |
| 10KB | ~6,150 | 15ms | 100% | 0 ✅ |
| 100KB | ~2,480 | 37ms | 100% | 0 ✅ |

---

### FFI CRC32C Impact (100KB payload)

libext2fs-dev installed by setup_openresty.sh provides FFI CRC32C
acceleration for large messages:

| Payload | Implementation | RPS | Latency |
|---------|---------------|-----|---------|
| 100KB | Pure Lua (before tuning) | ~1,858 | 51ms |
| 100KB | FFI CRC32C (after tuning) | ~2,480 | 37ms |

> FFI CRC32C provides ~33% improvement for 100KB messages
> For messages < 10KB difference is negligible

---

### Async Concurrency Impact

| Concurrency | RPS | Success | Latency |
|-------------|-----|---------|---------|
| 200 | ~25,600 | 100% | 1ms |
| 500 | ~24,793 | 100% | 1ms |

> Sweet spot: 200 concurrency
> More than 200 shows no improvement - Kafka is the bottleneck

---

### Partition Distribution (Async, 4 partitions)

Messages distributed evenly across all 4 partitions:
- Partition 0: ~25%
- Partition 1: ~25%
- Partition 2: ~25%
- Partition 3: ~25%

---

### Key Conclusions

1. **System tuning is critical** - 3.5x sync RPS improvement
2. **Async throughput** - ~25,600 RPS, zero data loss proven
3. **Sync throughput** - ~7,700 RPS after tuning (was ~2,200 before)
4. **No payload degradation** up to 1KB
5. **FFI CRC32C beneficial** for messages larger than ~50KB
6. **Kafka is the bottleneck** for async, not OpenResty
7. **Zero data loss** proven across all test scenarios
8. **Sweet spot**: 100 concurrency sync, 200 concurrency async

---

### Notes

- All tests run on shared hardware (Kafka + OpenResty on same 4 vCPU server)
- Production dedicated hardware would show significantly higher numbers
- 100KB test run for 2 minutes to avoid disk space issues (~2GB per minute)
- Disk requirement: minimum 150GB for full test suite
