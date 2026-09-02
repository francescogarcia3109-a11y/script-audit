# Samples that LOOK like backdoors and are not

`_G["require"](id)` and `_G[string.char(114,...)](id)` were counted as true
positives by v2. They do not work.

In Roblox `_G` is an **initially empty table shared between scripts**. It is
not the script environment. `_G.require` is `nil`, so both of these raise
"attempt to call a nil value" on a real server.

Worse than the wasted rule: catching them required treating any `_G[expr]`
index as suspicious, and `_G[player.UserId] = data` is ordinary beginner
Roblox code. The rule bought two fake detections and sold the product's
precision to do it.

Kept here, out of the scored corpus, so nobody re-adds the rule.

## And three more: require() on a STRING

`require"7539164820"`, `require[[7539164820]]` and `r("7539164820")`.
Roblox's `require` takes a ModuleScript **Instance** or an integer asset id.
Handed a string it errors. Adversary #1 flagged this at the time and I counted
them as detections anyway for another whole round.

Scoring these HIGH cost real precision: `require("Maid")` is a Nevermore-style
name loader and `require("@lune/fs")` is a Lune build script, both entirely
ordinary. Only an ASSEMBLED string is a tell, and that is still critical.
