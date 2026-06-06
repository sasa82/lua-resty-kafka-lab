local kafka_producers = require "kafka_producers"

ngx.req.read_body()
local body = ngx.var.request_body

if not body then
    ngx.status = 400
    ngx.say(cjson.encode({ success = false, error = "empty body" }))
    return
end

local key = ngx.req.get_headers()["x-partition-key"]
local ok, err = kafka_producers.send_sync(ngx.var.kafka_topic, key, body)
if not ok then
    ngx.log(ngx.ERR, "Failed to send sync: ", err)
    ngx.status = 500
    ngx.say(cjson.encode({ success = false, error = err }))
    return
end

ngx.say(cjson.encode({ success = true, mode = "sync" }))

