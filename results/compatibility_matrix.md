## Kafka Compatibility Matrix

### Test Environment
- OpenResty with lua-resty-kafka (patched fork)
- API version: 3 (default)
- Test method: HTTP POST to sync and async endpoints
- Message delivery confirmed by Kafka offset check
- Hardware: Hetzner CPX32 (4 vCPU, 8GB RAM)

### Patched Library Results (api_version=3, default)

| Type | Version | Kafka Version | Sync | Async | Messages | Result |
|------|---------|---------------|------|-------|----------|--------|
| ZK | 7.0.0 | Kafka 3.0.x | OK | OK | 2 | PASS |
| ZK | 7.2.0 | Kafka 3.2.x | OK | OK | 2 | PASS |
| ZK | 7.4.0 | Kafka 3.4.x | OK | OK | 2 | PASS |
| ZK | 7.5.0 | Kafka 3.5.x | OK | OK | 2 | PASS |
| ZK | 7.6.0 | Kafka 3.6.x | OK | OK | 2 | PASS |
| KRaft | 3.7.0 | Kafka 3.7.0 | OK | OK | 2 | PASS |
| KRaft | 3.8.0 | Kafka 3.8.0 | OK | OK | 2 | PASS |
| KRaft | 3.9.0 | Kafka 3.9.0 | OK | OK | 2 | PASS |
| KRaft | 4.0.0 | Kafka 4.0.0 | OK | OK | 2 | PASS |
| KRaft | 4.1.0 | Kafka 4.1.0 | OK | OK | 2 | PASS |
| KRaft | 4.2.0 | Kafka 4.2.0 | OK | OK | 2 | PASS |

### Original Library Results (api_version=1, default)

| Type | Version | Kafka Version | Sync | Async | Messages | Result |
|------|---------|---------------|------|-------|----------|--------|
| ZK | 7.0.0 | Kafka 3.0.x | OK | OK | 2 | PASS |
| ZK | 7.2.0 | Kafka 3.2.x | OK | OK | 2 | PASS |
| ZK | 7.4.0 | Kafka 3.4.x | OK | OK | 2 | PASS |
| ZK | 7.5.0 | Kafka 3.5.x | OK | OK | 2 | PASS |
| ZK | 7.6.0 | Kafka 3.6.x | OK | OK | 2 | PASS |
| KRaft | 3.7.0 | Kafka 3.7.0 | OK | OK | 2 | PASS |
| KRaft | 3.8.0 | Kafka 3.8.0 | OK | OK | 2 | PASS |
| KRaft | 3.9.0 | Kafka 3.9.0 | OK | OK | 2 | PASS |
| KRaft | 4.0.0 | Kafka 4.0.0 | FAIL | OK | 0 | FAIL |
| KRaft | 4.1.0 | Kafka 4.1.0 | FAIL | OK | 0 | FAIL |
| KRaft | 4.2.0 | Kafka 4.2.0 | FAIL | OK | 0 | FAIL |

### Comparison Summary

| Type | Version | Original | Patched |
|------|---------|----------|---------|
| ZK | 7.0-7.6 | PASS | PASS |
| KRaft | 3.7-3.9 | PASS | PASS |
| KRaft | 4.0+ | **FAIL** | **PASS** ✓ |

### Key Findings

- **Minimum supported Kafka version:** 3.0 (Confluent 7.0.0) - both libraries
- **KRaft 4.0+:** Only supported by patched library
- **Zero regressions:** All versions that worked before still work
- **New support:** KRaft Kafka 4.0, 4.1, 4.2 added by patched library

### Why KRaft 4.0+ Fails with Original Library

KRaft Kafka 4.0+ requires Produce API version 3+ which uses RecordBatch format.
Original library uses API version 1 (MessageSet format) which KRaft 4.0+ rejects:

    UnsupportedVersionException: Received request for api with key 0 (Produce)
    and unsupported version 1

### Bug Fixes in Patched Library

1. **RecordBatch format** - Produce API v3+ requires RecordBatch format (magic byte 2)
   with CRC32C checksum. Original library uses old MessageSet format (magic byte 0/1).

2. **Missing log_start_offset field** - Produce API v5+ response includes
   log_start_offset (int64) after timestamp. Missing this field caused
   byte misalignment in multi-partition responses.

3. **sendbuffer nil crash** - When Kafka returns an error for a topic/partition
   that was already cleared from the buffer, sendbuffer crashed with
   attempt to index local buffer (a nil value). Fixed with nil checks.

