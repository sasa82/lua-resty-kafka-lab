local producer = require "resty.kafka.producer"
local lock = require "resty.lock"

local brokers = {
    { host = "BROKER_IP", port = BROKER_PORT }
}

local POOL_SIZE = SYNC_POOL_SIZE
local LOCK_TIMEOUT = SYNC_LOCK_TIMEOUT

local sync_config = {
    producer_type = "sync",
}

local async_config = {
    producer_type = "async",
    flush_time = ASYNC_FLUSH_TIME,
    batch_num = ASYNC_BATCH_NUM,
    error_handle = function(topic, partition_id, messages, index, err, retryable)
        ngx.log(ngx.ERR, "async error handler: topic=", topic,
            " partition=", partition_id,
            " err=", err,
            " retryable=", tostring(retryable),
            " messages_count=", index)
    end,
}

local _M = {}
local _sync_producers = {}
local _async_producer = nil
local _pool_counter = 0

local function get_pool_idx()
    _pool_counter = (_pool_counter % POOL_SIZE) + 1
    return _pool_counter
end

function _M.get_sync()
    local idx = get_pool_idx()
    if not _sync_producers[idx] then
        local err
        _sync_producers[idx], err = producer:new(brokers, sync_config)
        if not _sync_producers[idx] then
            return nil, idx, err
        end
    end
    return _sync_producers[idx], idx, nil
end

function _M.get_async()
    if not _async_producer then
        local err
        _async_producer, err = producer:new(brokers, async_config)
        if not _async_producer then
            return nil, err
        end
    end
    return _async_producer
end

function _M.send_sync(topic, key, message)
    local p, idx, err = _M.get_sync()
    if not p then
        return nil, err
    end

    local lock_key = "sync_send_" .. idx
    local l = lock:new("producer_locks", { timeout = LOCK_TIMEOUT })
    local elapsed, err = l:lock(lock_key)
    if not elapsed then
        return nil, "failed to acquire lock: " .. err
    end

    local ok, err = p:send(topic, key, message)
    l:unlock()
    return ok, err
end

return _M

