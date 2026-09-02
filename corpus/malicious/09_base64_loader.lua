local blob = "bG9jYWwgcCA9IGdhbWU6R2V0U2VydmljZSgiUGxheWVycyIpCmZvciBfLCB2IGluIHBhaXJzKHA6R2V0UGxheWVycygpKSBkbyBwcmludCh2Lk5hbWUpIGVuZAo="
local decode = require(script.Parent.B64)
loadstring(decode(blob))()
