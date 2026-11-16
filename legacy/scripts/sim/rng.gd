extends RefCounted
## Deterministic PRNG (mulberry32). Never use randf()/RandomNumberGenerator in
## the economy sim: this keeps saves, offline maths and the balance bot
## reproducible across devices and engine versions.

var state: int = 1


func seed_with(v: int) -> void:
	state = v & 0xFFFFFFFF


## 32-bit multiply without 64-bit signed overflow.
static func _mul32(a: int, b: int) -> int:
	var lo := a * (b & 0xFFFF)
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & 0xFFFFFFFF


func next_u32() -> int:
	state = (state + 0x6D2B79F5) & 0xFFFFFFFF
	var t := state
	t = _mul32(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _mul32(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (t ^ (t >> 14)) & 0xFFFFFFFF


func randf01() -> float:
	return float(next_u32()) / 4294967296.0


## Poisson sample (Knuth). lam is small per tick, so this is cheap.
func poisson(lam: float) -> int:
	if lam <= 0.0:
		return 0
	var limit := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		p *= randf01()
		if p <= limit or k >= 50:
			break
		k += 1
	return k
