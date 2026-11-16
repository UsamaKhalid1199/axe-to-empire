extends Node
## Tiny SFX mixer: pooled players, random pitch, one looping chainsaw channel.

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _i := 0
var _saw: AudioStreamPlayer
var _last: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in ["chop", "clack", "coin", "pop", "build", "click", "saw", "cash", "fall"]:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	var saw: AudioStreamWAV = _streams.saw.duplicate()
	saw.loop_mode = AudioStreamWAV.LOOP_FORWARD
	saw.loop_begin = 0
	saw.loop_end = saw.data.size() / 2
	_saw = AudioStreamPlayer.new()
	_saw.stream = saw
	_saw.volume_db = -16.0
	add_child(_saw)


func play(name: String, db := 0.0, pitch := 1.0, min_gap := 0.03) -> void:
	if Game.mute or not _streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -1.0)) < min_gap:
		return
	_last[name] = now
	var p := _pool[_i]
	_i = (_i + 1) % _pool.size()
	p.stream = _streams[name]
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func saw(on: bool, pitch := 1.0) -> void:
	if Game.mute:
		on = false
	if on and not _saw.playing:
		_saw.play()
	elif not on and _saw.playing:
		_saw.stop()
	_saw.pitch_scale = pitch
