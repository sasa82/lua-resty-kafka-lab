local kafka_producers = require "kafka_producers"

local p, err = kafka_producers.get_async()
if not p then
    ngx.log(ngx.ERR, "Failed to get async producer: ", err)
    ngx.status = 500
    ngx.say(cjson.encode({ success = false, error = err }))
    return
end

ngx.req.read_body()
local body = ngx.var.request_body

if not body then
    ngx.status = 400
    ngx.say(cjson.encode({ success = false, error = "empty body" }))
    return
end

local key = ngx.req.get_headers()["x-partition-key"]
local ok, err = p:send(ngx.var.kafka_topic, key, body)
if not ok then
    ngx.log(ngx.ERR, "Failed to send async: ", err)
    ngx.status = 500
    ngx.say(cjson.encode({ success = false, error = err }))
    return
end

ngx.say(cjson.encode({ success = true, mode = "async" }))

