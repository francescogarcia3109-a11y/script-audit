# Real backdoors that this scanner will only ever INVENTORY, not flag

`16_method_self.lua`: `L.fn = require` … `function L:go(id) return self.fn(id) end`.

It is a genuine backdoor. It is also indistinguishable, in the source, from an
injectable/mockable loader — a normal testing pattern. Flagging it re-created a
false positive on an unrelated `Inventory:get` accessor, because the field map
is keyed on the bare field name with no receiver.

It gets a `medium` row and appears in the inventory. Promoting it to `high`
without tracking the receiver properly buys one detection and sells precision,
which is the trade that produced v1.
