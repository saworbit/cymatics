class_name AudioManager
extends Node

## File playback. Plasma Pong used FMOD + licensed cinematic tracks.
## We play CC0 orchestra under Kenney one-shots. No per-sample mixer.

const POOL := 12
const MUSIC_VOL := -14.0

var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _music: AudioStreamPlayer
var _music_on := true
var _duck := 0.0

var _hit_paddle: AudioStream
var _hit_wall: AudioStream
var _blast: AudioStream
var _parry: AudioStream
var _goal: AudioStream
var _sting: AudioStream
var _super: AudioStream

func _ready() -> void:
	_hit_paddle = _load_stream("res://assets/audio/sfx/pep.mp3")
	_hit_wall = _load_stream("res://assets/audio/sfx/hit_wall.ogg")
	_blast = _load_stream("res://assets/audio/sfx/blast.ogg")
	_parry = _load_stream("res://assets/audio/sfx/parry.ogg")
	_goal = _load_stream("res://assets/audio/sfx/goal.ogg")
	_sting = _load_stream("res://assets/audio/sfx/sting.ogg")
	_super = _load_stream("res://assets/audio/sfx/super.ogg")

	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = MUSIC_VOL
	var match_stream := _load_stream("res://assets/audio/music/match.ogg")
	if match_stream != null:
		_set_loop(match_stream, true)
		_music.stream = match_stream
	add_child(_music)
	if match_stream != null:
		_music.play()

	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if _music != null and is_instance_valid(_music):
			_music.stop()
			_music.stream = null
		for p in _pool:
			if is_instance_valid(p):
				p.stop()
				p.stream = null

func _exit_tree() -> void:
	if _music != null and is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	for p in _pool:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_pool.clear()
	_hit_paddle = null
	_hit_wall = null
	_blast = null
	_parry = null
	_goal = null
	_sting = null
	_super = null

func _process(delta: float) -> void:
	if _music == null or not _music_on:
		return
	_duck = move_toward(_duck, 0.0, delta * 2.4)
	_music.volume_db = MUSIC_VOL - _duck

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		_music_on = not _music_on
		if _music != null:
			_music.stream_paused = not _music_on

func update_fluid_drone(_avg_ke: float) -> void:
	pass

func update_ball_state(_speed: float, _curl: float, _norm_x: float) -> void:
	pass

func set_rally(_hits: int) -> void:
	pass

func register_paddle_movement(_speed: float, _norm_x: float) -> void:
	pass

func trigger_impact(impact_speed: float, _pos: Vector2, is_paddle: bool) -> void:
	var t := clampf(impact_speed / 1600.0, 0.0, 1.0)
	var pitch := lerpf(0.9, 1.22, t)
	if is_paddle:
		_play(_hit_paddle, -4.0, pitch)
	else:
		_play(_hit_wall, -7.0, pitch)
	_nudge_duck(1.5)

func trigger_parry(_impact_speed: float, _pos: Vector2) -> void:
	_play(_parry, -4.0, 1.06)
	_play(_hit_paddle, -8.0, 1.25)
	_nudge_duck(3.0)

func trigger_blast(charge_strength: float, _pos: Vector2) -> void:
	var s := clampf(charge_strength, 0.4, 1.4)
	_play(_blast, lerpf(-10.0, -4.0, s / 1.4), lerpf(0.92, 1.1, s / 1.4))
	_nudge_duck(2.0)

func trigger_super(_pos: Vector2) -> void:
	_play(_super, -3.0, 0.94)
	_play(_blast, -8.0, 0.78)
	_nudge_duck(4.0)

func trigger_goal(_scorer_id: int, smash: bool) -> void:
	_play(_goal, -4.0, 1.1 if smash else 1.0)
	if smash:
		_play(_super, -9.0, 0.85)
	_nudge_duck(5.0)

func trigger_sting(freq: float, amp: float) -> void:
	var pitch := clampf(freq / 520.0, 0.65, 1.7)
	_play(_sting, lerpf(-16.0, -7.0, clampf(amp, 0.0, 1.0)), pitch)

func _nudge_duck(db: float) -> void:
	_duck = minf(_duck + db, 8.0)

func _play(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if stream == null or _pool.is_empty():
		return
	var chosen: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _pool[_pool_i]
		_pool_i = (_pool_i + 1) % _pool.size()
		chosen.stop()
	chosen.stream = stream
	chosen.volume_db = vol_db
	chosen.pitch_scale = clampf(pitch, 0.55, 1.9)
	chosen.play()

func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("[AudioManager] missing %s" % path)
		return null
	return load(path) as AudioStream

func _set_loop(stream: AudioStream, on: bool) -> void:
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = on
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = on
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
