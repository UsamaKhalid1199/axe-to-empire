extends RefCounted
## Number / duration formatting for the UI.

const UNITS := ["K", "M", "B", "T", "aa", "ab", "ac", "ad"]


static func num(v: float) -> String:
	var a := absf(v)
	var sgn := "-" if v < 0.0 else ""
	if a < 10.0:
		return sgn + ("%.1f" % a).trim_suffix(".0")
	if a < 1000.0:
		return sgn + str(int(floor(a)))
	var i := -1
	while a >= 1000.0 and i < UNITS.size() - 1:
		a /= 1000.0
		i += 1
	var body := "%.2f" % a if a < 10.0 else ("%.1f" % a if a < 100.0 else str(int(a)))
	return sgn + body + UNITS[i]


static func dur(sec: float) -> String:
	var t := int(sec)
	if t >= 86400:
		return "%dd %dh" % [t / 86400, (t % 86400) / 3600]
	if t >= 3600:
		return "%dh %dm" % [t / 3600, (t % 3600) / 60]
	if t >= 60:
		return "%dm %ds" % [t / 60, t % 60]
	return "%ds" % t
