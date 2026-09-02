class_name AudioManager
extends Node

## Mixer front-end for the match. Plain Node child of main.tscn (not an autoload).
##
## Buses (assets/audio/default_bus_layout.tres):
##   Master (limiter) > Music (low-pass + sidechain compressor keyed from Impact)
##                    > SFX (glue compressor) > Impact, Blast, World
##                    > Drone (low-pass)
##                    > UI
##
## Gameplay one-shots are AudioStreamPlayer2D voices with attenuation disabled
## so the `pos` arguments pan by x. Music, UI, stingers and loops use plain
## players. Everything here runs on wall-clock time (process_mode ALWAYS, unscaled
## delta) so pause sounds and fades keep working at time_scale 0 or with the
## tree paused.
##
## Two soundtracks (set_soundtrack): "hope" is the CC0 orchestral loop
## (match.ogg, menu default) and "synth" is a three-stem procedural bed
## (tools/gen_music.py, match default). The stems are sample-locked WAV loops of
## identical length; layers fade in with the rally tier (pad / +pulse / +drive)
## and all three plus the heartbeat run during Cymatic Lock.
##
## Mix targets (approximate, after bus gains; files peak at -3 dBFS):
##   paddle hits ~-10 dBFS, UI ~-16, goal stingers ~-6, drone ~-24, music -10.

const POOL := 16
const STINGER_POOL := 3
const UI_POOL := 3
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_PATH := "res://assets/audio/music/match.ogg"
const STEM_DIR := "res://assets/audio/music/stems/"
const STEMS := {"pad": "synth_pad.wav", "pulse": "synth_pulse.wav", "drive": "synth_drive.wav"}
const STEM_BASE_DB := {"pad": -2.0, "pulse": -6.0, "drive": -5.0}
const STEM_RESYNC_S := 0.012
const SOUNDTRACK_XFADE := 1.8
const MUSIC_BASE_DB := -4.0
const MUSIC_XFADE := 1.6
const MUSIC_FADE_IN := 1.5
const MUSIC_FADE_TOGGLE := 0.4
const RETRIGGER_MS := 40
const DEFAULT_VOICE_CAP := 3
const LP_OPEN := 20500.0
const LP_PAUSE := 600.0
const LP_MATCH_END := 900.0
const LP_RALLY_CLOSED := 6500.0
const LP_THEATRE := 420.0
const THEATRE_HOLD_S := 1.4
const CHARGE_RAMP_S := 0.9
const CHARGE_MAX_HOLD_S := 4.0
const ORBIT_RAMP_S := 2.5
const ORBIT_FALLBACK_S := 2.0
const LOCK_PULSE_S := 0.5
const AIM_TICK_MS := 120
const ARENA_W := 1920.0
const PITCH_JITTER := 0.04
const GAIN_JITTER_DB := 1.5
const RALLY_TIER_EVERY := 4
const SILENT_DB := -80.0

## key -> file list (relative to SFX_DIR). Multi-entry keys play round-robin.
const LIB := {
	"paddle_hit": ["gen/paddle_hit_1.wav", "gen/paddle_hit_2.wav", "gen/paddle_hit_3.wav"],
	"pep": ["pep.mp3"],
	"wall_hit": ["gen/wall_hit_1.wav", "gen/wall_hit_2.wav", "gen/wall_hit_3.wav"],
	"wall_kenney": ["hit_wall.ogg"],
	"brick_hit": ["gen/brick_hit_1.wav", "gen/brick_hit_2.wav"],
	"brick_shatter": ["gen/brick_shatter.wav"],
	"blast": ["gen/blast.wav"],
	"blast_kenney": ["blast.ogg"],
	"blast_ready": ["gen/blast_ready.wav"],
	"super": ["gen/super.wav"],
	"super_kenney": ["super.ogg"],
	"parry": ["gen/parry.wav"],
	"parry_kenney": ["parry.ogg"],
	"sting": ["sting.ogg"],
	"goal_kenney": ["goal.ogg"],
	"goal_p1": ["gen/goal_p1.wav"],
	"goal_p2": ["gen/goal_p2.wav"],
	"set_won": ["gen/set_won.wav"],
	"match_won": ["gen/match_won.wav"],
	"match_lost": ["gen/match_lost.wav"],
	"rally_tier_1": ["gen/rally_tier_1.wav"],
	"rally_tier_2": ["gen/rally_tier_2.wav"],
	"rally_tier_3": ["gen/rally_tier_3.wav"],
	"rally_tier_4": ["gen/rally_tier_4.wav"],
	"overdrive_riser": ["gen/overdrive_riser.wav"],
	"lock_enter": ["gen/lock_enter.wav"],
	"powerup_spawn": ["gen/powerup_spawn.wav"],
	"powerup_collect": ["gen/powerup_collect.wav"],
	"powerup_expire": ["gen/powerup_expire.wav"],
	"stun": ["gen/stun.wav"],
	"stun_bolt_fire": ["gen/stun_bolt_fire.wav"],
	"multiball_split": ["gen/multiball_split.wav"],
	"hazard_vortex": ["gen/hazard_vortex.wav"],
	"stage_intro": ["gen/stage_intro.wav"],
	"stage_complete": ["gen/stage_complete.wav"],
	"ui_navigate": ["gen/ui_navigate.wav"],
	"ui_confirm": ["gen/ui_confirm.wav"],
	"ui_back": ["gen/ui_back.wav"],
	"menu_open": ["gen/menu_open.wav"],
	"pause": ["gen/pause.wav"],
	"resume": ["gen/resume.wav"],
	"countdown_tick": ["gen/countdown_tick.wav"],
	"suck_loop": ["gen/suck_loop.wav"],
	"stream_loop": ["gen/stream_loop.wav"],
	"hydro_rush_loop": ["gen/hydro_rush_loop.wav"],
	"drone_calm_loop": ["gen/drone_calm_loop.wav"],
	"drone_turbulent_loop": ["gen/drone_turbulent_loop.wav"],
	"heartbeat_loop": ["gen/heartbeat_loop.wav"],
	# Phase 2 signature moments.
	"blast_charge_loop": ["gen/blast_charge_loop.wav"],
	"blast_charge_release_1": ["gen/blast_charge_release_1.wav"],
	"blast_charge_release_2": ["gen/blast_charge_release_2.wav"],
	"blast_charge_release_3": ["gen/blast_charge_release_3.wav"],
	"suck_capture": ["gen/suck_capture.wav"],
	"orbit_loop": ["gen/orbit_loop.wav"],
	"slingshot_release": ["gen/slingshot_release.wav"],
	"goal_shatter": ["gen/goal_shatter.wav"],
	"brick_shard_tinkle": ["gen/brick_shard_tinkle.wav"],
	"serve_beat_1": ["gen/serve_beat_1.wav"],
	"serve_beat_2": ["gen/serve_beat_2.wav"],
	"serve_beat_3": ["gen/serve_beat_3.wav"],
	"serve_warning": ["gen/serve_warning.wav"],
	"lock_pulse": ["gen/lock_pulse.wav"],
	"perfect_star": ["gen/perfect_star.wav"],
	"wall_ripple": ["gen/wall_ripple.wav"],
}
const LOOP_KEYS := ["suck_loop", "stream_loop", "hydro_rush_loop", "drone_calm_loop", "drone_turbulent_loop", "heartbeat_loop", "blast_charge_loop", "orbit_loop"]

# --- voices -----------------------------------------------------------------
var _pool: Array[AudioStreamPlayer2D] = []
var _pool_i := 0
var _stingers: Array[AudioStreamPlayer] = []
var _ui: Array[AudioStreamPlayer] = []
var _voice_key: Dictionary = {}       # instance id -> key
var _last_play_ms: Dictionary = {}    # key -> msec of last trigger
var _rr: Dictionary = {}              # key -> next round-robin index
var _lib: Dictionary = {}             # key -> Array[AudioStream]
var _missing: Dictionary = {}

# --- music ------------------------------------------------------------------
## menu_manager pokes `_music_on` / `_music` directly; keep both names.
var _music: AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_stream: AudioStream
var _music_len := 0.0
var _music_on := true
var _music_applied_on := true
var _music_gain := 0.0
var _music_gain_target := 1.0
var _music_fade_rate := 1.0 / MUSIC_FADE_IN
var _xfade_a := 1.0
var _xfade_b := 0.0
var _duck := 0.0
var _music_lp: AudioEffectLowPassFilter
var _lp_cur := LP_OPEN
var _lp_rally := LP_RALLY_CLOSED
var _lp_pause := LP_OPEN
var _lp_end := LP_OPEN
var _rally_hits := 0
var _rally_tier := 0
var _lp_theatre := LP_OPEN
var _theatre_t := 0.0

# --- stems ------------------------------------------------------------------
var _stems: Dictionary = {}           # name -> AudioStreamPlayer
var _stem_gain: Dictionary = {}       # name -> linear (slewed)
var _stem_len := 0.0
var _stem_ok := false
var _soundtrack := "hope"
var _hope_w := 1.0                    # 1 = hope, 0 = synth (crossfade weight)
var _stem_check_t := 0.0
var _stem_resyncs := 0
var _stem_max_drift := 0.0

# --- loops ------------------------------------------------------------------
var _drone_calm: AudioStreamPlayer
var _drone_turb: AudioStreamPlayer
var _drone_lp: AudioEffectLowPassFilter
var _ke_smooth := 0.0
var _drone_bus_ok := false
var _heart: AudioStreamPlayer
var _heart_gain := 0.0
var _heart_on := false
var _suck: Array[AudioStreamPlayer2D] = []
var _stream: Array[AudioStreamPlayer2D] = []
var _rush: Array[AudioStreamPlayer2D] = []
var _suck_target := [0.0, 0.0]
var _stream_target := [0.0, 0.0]
var _rush_target := [0.0, 0.0]
var _suck_gain := [0.0, 0.0]
var _stream_gain := [0.0, 0.0]
var _rush_gain := [0.0, 0.0]
var _charge: Array[AudioStreamPlayer2D] = []
var _charge_t := [-1.0, -1.0]        # seconds held, <0 = idle
var _charge_paddle: Array = [null, null]
var _orbit: Array[AudioStreamPlayer2D] = []
var _orbit_t := [-1.0, -1.0]
var _orbit_gain := [0.0, 0.0]
var _orbit_paddle: Array = [null, null]
var _lock_pulse_t := 0.0
var _last_shatter_ms := -100000
var _last_aim_ms := -100000

# --- binding ----------------------------------------------------------------
var _bound: Dictionary = {}           # instance id -> true
var _bound_ball: Ball
var _bound_paddles: Array = []
var _match_stinger_ms := -100000
var _pending_set_win := -1
var _pending_set_ms := 0
var _bus_base: Dictionary = {}
var _last_tick_ms := 0
var _paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tick_ms = Time.get_ticks_msec()
	for b in ["Master", "Music", "SFX", "Impact", "Blast", "World", "Drone", "UI"]:
		var idx := AudioServer.get_bus_index(b)
		_bus_base[b] = AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0
		if idx < 0:
			push_warning("[AudioManager] bus '%s' missing; check assets/audio/default_bus_layout.tres" % b)
	_music_lp = _find_effect("Music", AudioEffectLowPassFilter) as AudioEffectLowPassFilter
	_drone_lp = _find_effect("Drone", AudioEffectLowPassFilter) as AudioEffectLowPassFilter

	_build_music()
	_build_stems()
	_build_pools()
	_build_loops()

func _build_music() -> void:
	_music_stream = _load_stream(MUSIC_PATH)
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_music = _music_a
	if _music_stream == null:
		return
	_set_loop(_music_stream, false)  # we crossfade the wrap ourselves
	_music_len = _music_stream.get_length()
	_music_a.stream = _music_stream
	_music_b.stream = _music_stream
	_music_a.volume_db = SILENT_DB
	_music_b.volume_db = SILENT_DB
	_music_a.play()
	_music_gain = 0.0
	_music_gain_target = 1.0
	_music_fade_rate = 1.0 / MUSIC_FADE_IN

func _build_stems() -> void:
	var ok := true
	var len_frames := -1
	for name in STEMS.keys():
		var stream := _load_stream(STEM_DIR + STEMS[name])
		var p := _make_player("Music")
		p.volume_db = SILENT_DB
		_stems[name] = p
		_stem_gain[name] = 0.0
		if stream == null:
			ok = false
			continue
		_set_loop(stream, true)
		p.stream = stream
		if stream is AudioStreamWAV:
			var frames := (stream as AudioStreamWAV).data.size() / (2 * (2 if (stream as AudioStreamWAV).stereo else 1))
			if len_frames < 0:
				len_frames = frames
			elif frames != len_frames:
				push_warning("[AudioManager] stem %s length %d != %d; stems must be sample-identical" % [name, frames, len_frames])
				ok = false
		_stem_len = stream.get_length()
	_stem_ok = ok and _stems.size() == STEMS.size()

func _build_pools() -> void:
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 1.0e6
		p.attenuation = 0.0
		# Net pan = panning_strength * ProjectSettings 2d_panning_strength (0.5).
		p.panning_strength = 1.4
		p.bus = _bus("Impact")
		add_child(p)
		_pool.append(p)
	for i in STINGER_POOL:
		_stingers.append(_make_player("World"))
	for i in UI_POOL:
		_ui.append(_make_player("UI"))

func _build_loops() -> void:
	_drone_calm = _make_loop_player("drone_calm_loop", "Drone")
	_drone_turb = _make_loop_player("drone_turbulent_loop", "Drone")
	_drone_bus_ok = AudioServer.get_bus_index("Drone") >= 0
	_heart = _make_loop_player("heartbeat_loop", "World")
	for side in 2:
		_suck.append(_make_loop_player2d("suck_loop", "World"))
		_stream.append(_make_loop_player2d("stream_loop", "World"))
		_rush.append(_make_loop_player2d("hydro_rush_loop", "World"))
		_charge.append(_make_loop_player2d("blast_charge_loop", "Blast"))
		_orbit.append(_make_loop_player2d("orbit_loop", "World"))

func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = _bus(bus)
	add_child(p)
	return p

func _make_loop_player(key: String, bus: String) -> AudioStreamPlayer:
	var p := _make_player(bus)
	p.stream = _stream_for(key)
	p.volume_db = SILENT_DB
	return p

func _make_loop_player2d(key: String, bus: String) -> AudioStreamPlayer2D:
	var p := AudioStreamPlayer2D.new()
	p.max_distance = 1.0e6
	p.attenuation = 0.0
	p.panning_strength = 1.4
	p.bus = _bus(bus)
	p.stream = _stream_for(key)
	p.volume_db = SILENT_DB
	add_child(p)
	return p

func _exit_tree() -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null
		elif c is AudioStreamPlayer2D:
			(c as AudioStreamPlayer2D).stop()
			(c as AudioStreamPlayer2D).stream = null
	# Stopped playbacks are retired on the mix thread, one mix period later
	# (the headless dummy driver mixes 4096 frames, ~93 ms). Without this
	# settle the still-playing loops and music show up as leaked at exit.
	# Only runs when this node leaves the tree, i.e. at quit.
	OS.delay_msec(120)
	_pool.clear()
	_stingers.clear()
	_ui.clear()
	_suck.clear()
	_stream.clear()
	_rush.clear()
	_charge.clear()
	_orbit.clear()
	_stems.clear()
	_lib.clear()
	_music_stream = null

# ============================================================ per-frame (unscaled)
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_tick_ms) / 1000.0, 0.0, 0.1)
	_last_tick_ms = now

	if _music_on != _music_applied_on:
		set_music_enabled(_music_on)

	_tick_music(dt)
	_tick_stems(dt)
	_tick_music_filter(dt)
	_tick_loops(dt)
	_tick_moments(dt)
	_tick_binding(now)

func _tick_music(dt: float) -> void:
	if _music_a == null or _music_stream == null:
		return
	_music_gain = move_toward(_music_gain, _music_gain_target, dt * _music_fade_rate)
	_duck = move_toward(_duck, 0.0, dt * 3.0)

	# Seamless wrap: start the idle player MUSIC_XFADE before the end and crossfade.
	if _music_len > MUSIC_XFADE * 2.0 and _music_gain_target > 0.0:
		var lead := _music_a if _xfade_a >= _xfade_b else _music_b
		var other := _music_b if lead == _music_a else _music_a
		if lead.playing and not lead.stream_paused and not other.playing:
			if lead.get_playback_position() >= _music_len - MUSIC_XFADE:
				other.volume_db = SILENT_DB
				other.play(0.0)
		if other.playing:
			var step := dt / MUSIC_XFADE
			if lead == _music_a:
				_xfade_b = minf(_xfade_b + step, 1.0)
				_xfade_a = 1.0 - _xfade_b
			else:
				_xfade_a = minf(_xfade_a + step, 1.0)
				_xfade_b = 1.0 - _xfade_a
			if (lead == _music_a and _xfade_b >= 1.0) or (lead == _music_b and _xfade_a >= 1.0):
				lead.stop()
				_music = other
		elif not lead.playing and _music_applied_on and _music_gain_target > 0.0:
			# Both silent (stream ended without a crossfade partner). Restart.
			lead.play(0.0)
			if lead == _music_a:
				_xfade_a = 1.0
				_xfade_b = 0.0
			else:
				_xfade_b = 1.0
				_xfade_a = 0.0

	_music_a.volume_db = _music_db(_xfade_a)
	_music_b.volume_db = _music_db(_xfade_b)

	if _music_gain <= 0.0 and _music_gain_target <= 0.0 and not _music_applied_on:
		if not _music_a.stream_paused:
			_music_a.stream_paused = true
		if not _music_b.stream_paused:
			_music_b.stream_paused = true

func _music_db(weight: float) -> float:
	var lin := weight * _music_gain * _hope_w
	if lin <= 0.0005:
		return SILENT_DB
	return MUSIC_BASE_DB + linear_to_db(lin) - _duck

## Stem set: three sample-locked loops on the Music bus. Layers follow the rally
## tier (0 = pad, 1 = +pulse, 2+ = +drive; Lock = all). They run at silent volume
## when their layer is off so the players never drift apart; every second the
## positions are compared and any straggler is snapped back to the pad.
func _tick_stems(dt: float) -> void:
	var want_synth := _soundtrack == "synth" and _stem_ok
	_hope_w = move_toward(_hope_w, 0.0 if want_synth else 1.0, dt / SOUNDTRACK_XFADE)
	var synth_w := 1.0 - _hope_w
	if _stems.is_empty():
		return
	var pad: AudioStreamPlayer = _stems.get("pad")
	if pad == null:
		return
	var any_playing := pad.playing
	if want_synth and not any_playing and _music_applied_on:
		_start_stems()
		any_playing = true
	if not any_playing:
		return
	var locked := _heart_on
	var targets := {
		"pad": 1.0,
		"pulse": 1.0 if (_rally_tier >= 1 or locked) else 0.0,
		"drive": 1.0 if (_rally_tier >= 2 or locked) else 0.0,
	}
	var all_silent := true
	for name in _stems.keys():
		var p: AudioStreamPlayer = _stems[name]
		var tgt: float = targets.get(name, 0.0)
		var g: float = _stem_gain[name]
		g = move_toward(g, tgt, dt / (1.2 if tgt > g else 2.0))
		_stem_gain[name] = g
		var lin := g * synth_w * _music_gain
		if lin <= 0.0005:
			p.volume_db = SILENT_DB
		else:
			all_silent = false
			p.volume_db = float(STEM_BASE_DB[name]) + linear_to_db(lin) - _duck
	# Fully faded out: stop the stems so the mix thread is not looping silence.
	if all_silent and (synth_w <= 0.0005 or not _music_applied_on):
		for name in _stems.keys():
			(_stems[name] as AudioStreamPlayer).stop()
	# Hope players idle while synth owns the mix; resume from the same spot later.
	if _music_a != null and _music_stream != null and _music_applied_on:
		var park := _hope_w <= 0.0005
		if _music_a.stream_paused != park:
			_music_a.stream_paused = park
			_music_b.stream_paused = park
	# Sample lock check.
	_stem_check_t -= dt
	if _stem_check_t <= 0.0 and _stem_len > 0.0:
		_stem_check_t = 1.0
		var ref := pad.get_playback_position()
		for name in _stems.keys():
			if name == "pad":
				continue
			var p: AudioStreamPlayer = _stems[name]
			if not p.playing:
				continue
			var d := absf(p.get_playback_position() - ref)
			d = minf(d, _stem_len - d)
			_stem_max_drift = maxf(_stem_max_drift, d)
			if d > STEM_RESYNC_S:
				p.seek(ref)
				_stem_resyncs += 1

func _start_stems() -> void:
	# Start all three in the same frame so they share a mix start.
	for name in STEMS.keys():
		var p: AudioStreamPlayer = _stems.get(name)
		if p == null or p.stream == null:
			continue
		p.volume_db = SILENT_DB
		p.stream_paused = false
		p.play(0.0)
	_stem_check_t = 1.0

## Diagnostics for the lab / screenshot drivers.
func get_stem_drift_ms() -> float:
	return _stem_max_drift * 1000.0

func get_stem_resyncs() -> int:
	return _stem_resyncs

func get_soundtrack() -> String:
	return _soundtrack

func _tick_music_filter(dt: float) -> void:
	if _music_lp == null:
		return
	var target := minf(_lp_rally, minf(_lp_pause, minf(_lp_end, _lp_theatre)))
	# Log-domain slew so opening and closing feel symmetric.
	var cur_l := log(_lp_cur)
	var tgt_l := log(target)
	var rate := 6.0 if target < _lp_cur else 2.5
	cur_l = move_toward(cur_l, tgt_l, dt * rate)
	_lp_cur = exp(cur_l)
	if absf(_music_lp.cutoff_hz - _lp_cur) > 1.0:
		_music_lp.cutoff_hz = _lp_cur

func _tick_loops(dt: float) -> void:
	# Heartbeat (cymatic lock).
	if _heart != null:
		_heart_gain = move_toward(_heart_gain, 1.0 if _heart_on else 0.0, dt * (4.0 if _heart_on else 2.0))
		_apply_loop_gain(_heart, _heart_gain, -6.0)

	# Suck / stream / hydro rush per side. Targets decay unless refreshed.
	for side in 2:
		_suck_gain[side] = move_toward(_suck_gain[side], _suck_target[side], dt * 6.0)
		_stream_gain[side] = move_toward(_stream_gain[side], _stream_target[side], dt * 6.0)
		_rush_gain[side] = move_toward(_rush_gain[side], _rush_target[side], dt * 5.0)
		_rush_target[side] = move_toward(_rush_target[side], 0.0, dt * 4.0)
		if side < _suck.size():
			_apply_loop_gain(_suck[side], _suck_gain[side], -4.0)
		if side < _stream.size():
			_apply_loop_gain(_stream[side], _stream_gain[side], -6.0)
		if side < _rush.size():
			_apply_loop_gain(_rush[side], _rush_gain[side], -12.0)

	# Drone: crossfade calm <-> turbulent by smoothed kinetic energy.
	if _drone_calm != null and _drone_turb != null:
		var ke := _ke_smooth
		var calm_w := (1.0 - ke) * (0.35 + 0.65 * ke * 0.4 + 0.3)
		var turb_w := ke
		_apply_loop_gain(_drone_calm, clampf(calm_w, 0.0, 1.0), -8.0)
		_apply_loop_gain(_drone_turb, clampf(turb_w, 0.0, 1.0), -4.0)
		if _drone_lp != null:
			var cut := lerpf(320.0, 4200.0, ke * ke)
			if absf(_drone_lp.cutoff_hz - cut) > 2.0:
				_drone_lp.cutoff_hz = cut

## Charge / orbit ramps, goal-theatre filter hold and the Lock pulse. Unscaled.
func _tick_moments(dt: float) -> void:
	if _theatre_t > 0.0:
		_theatre_t -= dt
		if _theatre_t <= 0.0:
			_lp_theatre = LP_OPEN
	for side in 2:
		# Blast charge: pitch and level climb for CHARGE_RAMP_S, then hold.
		if _charge_t[side] >= 0.0 and side < _charge.size():
			_charge_t[side] += dt
			var p := _charge[side]
			var cp = _charge_paddle[side]
			var still: bool = float(_charge_t[side]) < CHARGE_MAX_HOLD_S
			if cp != null and is_instance_valid(cp):
				p.global_position = cp.global_position
				if cp.has_method("is_charging") and _charge_t[side] > 0.1 and not bool(cp.call("is_charging")):
					still = false
			if not still:
				_stop_charge(side)
			else:
				var k := clampf(_charge_t[side] / CHARGE_RAMP_S, 0.0, 1.0)
				p.pitch_scale = lerpf(1.0, 1.45, k)
				p.volume_db = lerpf(-14.0, -5.0, k)
		# Orbit: rises while the paddle keeps the ball captured.
		if side < _orbit.size():
			var op := _orbit[side]
			if _orbit_t[side] >= 0.0:
				_orbit_t[side] += dt
				var opd = _orbit_paddle[side]
				var keep := false
				if opd != null and is_instance_valid(opd):
					op.global_position = opd.global_position
					var sk = opd.get("is_sucking")
					keep = sk is bool and sk
					if keep and _bound_ball != null and is_instance_valid(_bound_ball):
						var cap = _bound_ball.get("captured_by")
						if cap != null:
							keep = cap == opd
						else:
							keep = _orbit_t[side] < ORBIT_FALLBACK_S
				if not keep:
					_orbit_t[side] = -1.0
				else:
					var k := clampf(_orbit_t[side] / ORBIT_RAMP_S, 0.0, 1.0)
					op.pitch_scale = lerpf(1.0, 1.6, k)
			var tgt := 1.0 if _orbit_t[side] >= 0.0 else 0.0
			_orbit_gain[side] = move_toward(_orbit_gain[side], tgt, dt * (8.0 if tgt > 0.0 else 5.0))
			_apply_loop_gain(op, _orbit_gain[side], -6.0)
	# Lost-ball pulse: soft sonar ping every LOCK_PULSE_S while in Cymatic Lock.
	if _heart_on and _bound_ball != null and is_instance_valid(_bound_ball):
		_lock_pulse_t -= dt
		if _lock_pulse_t <= 0.0:
			_lock_pulse_t = LOCK_PULSE_S
			_play2d("lock_pulse", "World", _bound_ball.global_position, -12.0, 1.0, false, 2)
	else:
		_lock_pulse_t = 0.0

func _stop_charge(side: int) -> void:
	_charge_t[side] = -1.0
	_charge_paddle[side] = null
	if side < _charge.size() and _charge[side].playing:
		_charge[side].stop()

func _apply_loop_gain(p, gain: float, top_db: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	if p.stream == null:
		return
	if gain <= 0.001:
		if p.playing:
			p.stop()
		p.volume_db = SILENT_DB
		return
	if not p.playing:
		p.play()
	p.volume_db = top_db + linear_to_db(gain)

func _tick_binding(now: int) -> void:
	if _pending_set_win >= 0 and now - _pending_set_ms > 80:
		var w := _pending_set_win
		_pending_set_win = -1
		if now - _match_stinger_ms > 300:
			trigger_set_won(w)
	if _bound_ball != null and is_instance_valid(_bound_ball):
		var locked: bool = _bound_ball.is_in_cymatic_lock
		if locked != _heart_on:
			trigger_cymatic_lock(locked)
	for i in _bound_paddles.size():
		var p = _bound_paddles[i]
		if p == null or not is_instance_valid(p):
			continue
		var side := 0 if p.player_id == 0 else 1
		var pos: Vector2 = p.global_position
		var strength := 0.6 + 0.4 * clampf(float(p.momentum), 0.0, 1.0)
		trigger_suck(bool(p.is_sucking), pos, strength)
		trigger_stream(bool(p.is_shooting), pos, strength)

# ============================================================ input
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		set_music_enabled(not is_music_enabled())

# ============================================================ music API
func set_music_enabled(enabled: bool) -> void:
	_music_on = enabled
	_music_applied_on = enabled
	_music_gain_target = 1.0 if enabled else 0.0
	_music_fade_rate = 1.0 / MUSIC_FADE_TOGGLE
	if _music_a != null:
		_music_a.stream_paused = false
		_music_b.stream_paused = false
		if enabled and not _music_a.playing and not _music_b.playing and _music_stream != null:
			_xfade_a = 1.0
			_xfade_b = 0.0
			_music = _music_a
			_music_a.play(0.0)
	if enabled and _soundtrack == "synth" and _stem_ok:
		var pad: AudioStreamPlayer = _stems.get("pad")
		if pad != null and not pad.playing:
			_start_stems()

func is_music_enabled() -> bool:
	return _music_on

## "hope" = match.ogg (menu default), "synth" = generated stems (match default).
## Crossfades over SOUNDTRACK_XFADE seconds; falls back to hope if the stems
## are missing.
func set_soundtrack(name: String) -> void:
	if name != "hope" and name != "synth":
		push_warning("[AudioManager] unknown soundtrack '%s'" % name)
		return
	if name == "synth" and not _stem_ok:
		name = "hope"
	if name == _soundtrack:
		return
	_soundtrack = name
	if name == "synth":
		if _music_applied_on:
			_start_stems()
	elif _music_a != null and _music_stream != null and _music_applied_on:
		_music_a.stream_paused = false
		_music_b.stream_paused = false
		if not _music_a.playing and not _music_b.playing:
			_xfade_a = 1.0
			_xfade_b = 0.0
			_music = _music_a
			_music_a.play(0.0)

func set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var base: float = _bus_base.get(bus, 0.0)
	if linear <= 0.001:
		AudioServer.set_bus_volume_db(idx, SILENT_DB)
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, base + linear_to_db(clampf(linear, 0.0001, 1.0)))

## Legacy slider names (menu_manager).
func set_master_volume(linear: float) -> void:
	set_bus_volume("Master", linear)

func set_music_volume(linear: float) -> void:
	set_bus_volume("Music", linear)

func set_sfx_volume(linear: float) -> void:
	set_bus_volume("SFX", linear)

# ============================================================ continuous state
func update_fluid_drone(avg_ke: float) -> void:
	var norm := clampf(avg_ke / 4500.0, 0.0, 1.0)
	_ke_smooth = lerpf(_ke_smooth, norm, 0.04)

func update_ball_state(_speed: float, _curl: float, _norm_x: float) -> void:
	pass  # cheap on purpose; ball hits carry the information

func set_rally(hits: int) -> void:
	if hits == _rally_hits:
		return
	var prev := _rally_hits
	_rally_hits = hits
	var t := clampf(float(hits) / 16.0, 0.0, 1.0)
	_lp_rally = exp(lerpf(log(LP_RALLY_CLOSED), log(LP_OPEN), t))
	if hits <= 0:
		_rally_tier = 0
		return
	var tier := clampi(hits / RALLY_TIER_EVERY, 0, 4)
	if tier > _rally_tier and hits > prev:
		_rally_tier = tier
		trigger_rally_tier(tier)

func register_paddle_movement(speed: float, norm_x: float) -> void:
	var side := 0 if norm_x < 0.5 else 1
	var g := clampf(speed / 1100.0, 0.0, 1.0)
	_rush_target[side] = maxf(_rush_target[side], g)
	if side < _rush.size():
		_rush[side].global_position = Vector2(norm_x * ARENA_W, 540.0)
		_rush[side].pitch_scale = lerpf(0.9, 1.15, g)

# ============================================================ gameplay triggers
func trigger_impact(impact_speed: float, pos: Vector2, is_paddle: bool) -> void:
	var t := clampf(impact_speed / 1600.0, 0.0, 1.0)
	var pitch := lerpf(0.9, 1.22, t)
	if is_paddle:
		_play2d("paddle_hit", "Impact", pos, lerpf(-8.0, -2.0, t), pitch, true, 3)
		_play2d("pep", "Impact", pos, lerpf(-18.0, -11.0, t), pitch, true, 2)
	else:
		_play2d("wall_hit", "Impact", pos, lerpf(-11.0, -4.0, t), pitch, true, 3)

## Ball calls this for wall contacts when it exists (else trigger_impact).
func trigger_wall_hit(pos: Vector2, speed: float) -> void:
	trigger_impact(speed * 0.7, pos, false)
	var t := clampf(speed / 1600.0, 0.0, 1.0)
	_play2d("wall_ripple", "World", pos, lerpf(-16.0, -8.0, t), lerpf(0.95, 1.1, t), true, 2)

## Perfect hit: parry crack plus the crystalline star layer.
func trigger_parry(impact_speed: float, pos: Vector2) -> void:
	var t := clampf(impact_speed / 1600.0, 0.0, 1.0)
	_play2d("parry", "Impact", pos, lerpf(-4.0, 0.0, t), lerpf(1.0, 1.08, t), true, 2)
	_play2d("perfect_star", "Impact", pos, lerpf(-9.0, -4.0, t), 1.0, true, 2)
	_nudge_duck(2.0)

# --- signature moments (phase 2) --------------------------------------------
func trigger_blast_charge_started(pos: Vector2, paddle = null) -> void:
	var side := _side_of(pos, paddle)
	if side >= _charge.size() or _charge[side].stream == null:
		return
	var p := _charge[side]
	_charge_paddle[side] = paddle
	_charge_t[side] = 0.0
	p.global_position = pos
	p.pitch_scale = 1.0
	p.volume_db = -14.0
	p.play(0.0)

## power: 0..1 (or the paddle's 0.4..1.4 strength); tiers at <0.5, <0.9, else 3.
func trigger_blast_charge_released(pos: Vector2, power: float, paddle = null) -> void:
	var side := _side_of(pos, paddle)
	if side < _charge.size():
		_stop_charge(side)
	var tier := 1 if power < 0.5 else (2 if power < 0.9 else 3)
	var k := clampf(power / 1.2, 0.0, 1.0)
	_play2d("blast_charge_release_%d" % tier, "Blast", pos, lerpf(-9.0, -2.0, k), lerpf(1.04, 0.96, k), true, 2)
	_nudge_duck(2.0 + float(tier))

func trigger_suck_captured(pos: Vector2, paddle = null) -> void:
	var side := _side_of(pos, paddle)
	_play2d("suck_capture", "World", pos, -5.0, 1.0, true, 2)
	if side < _orbit.size():
		_orbit_paddle[side] = paddle
		_orbit_t[side] = 0.0
		_orbit[side].global_position = pos
		_orbit[side].pitch_scale = 1.0

func trigger_slingshot(pos: Vector2, speed: float, paddle = null) -> void:
	var side := _side_of(pos, paddle)
	if side < _orbit.size():
		_orbit_t[side] = -1.0
	var t := clampf(speed / 2000.0, 0.0, 1.0)
	_play2d("slingshot_release", "Blast", pos, lerpf(-8.0, -2.0, t), lerpf(0.96, 1.08, t), true, 2)
	_nudge_duck(4.0)

func trigger_serve_aimed(_dir: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_aim_ms < AIM_TICK_MS:
		return
	_last_aim_ms = now
	_play_ui("ui_navigate", -16.0, randf_range(1.05, 1.15))

func trigger_serve_beat(beat: int) -> void:
	var b := clampi(beat, 1, 3)
	_play_ui("serve_beat_%d" % b, -6.0 if b < 3 else -4.0, 1.0)

func trigger_serve_warning(seconds_left: float) -> void:
	var urgency := clampf(1.0 - seconds_left / 3.0, 0.0, 1.0)
	_play_ui("serve_warning", lerpf(-9.0, -5.0, urgency), lerpf(1.0, 1.08, urgency))

func trigger_auto_served(_server_id: int) -> void:
	_play_ui("countdown_tick", -8.0, 0.75)

## Goal theatre: glass shatter into sub boom; music low-passes hard for the
## slow-mo hold (wall-clock THEATRE_HOLD_S; TimeController's slow-mo does not
## affect this node).
func trigger_goal_theatre(_side: int, _pos: Vector2) -> void:
	_last_shatter_ms = Time.get_ticks_msec()
	_play_stinger("goal_shatter", -1.0, 1.0)
	_lp_theatre = LP_THEATRE
	_theatre_t = THEATRE_HOLD_S
	_nudge_duck(6.0)

func trigger_ball_shattered(pos: Vector2, _vel: Vector2) -> void:
	_play2d("brick_shard_tinkle", "Impact", pos, -6.0, 0.9, true, 2)
	if Time.get_ticks_msec() - _last_shatter_ms > 300:
		_last_shatter_ms = Time.get_ticks_msec()
		_play_stinger("goal_shatter", -3.0, 1.0)
		_nudge_duck(4.0)

func _side_of(pos: Vector2, paddle = null) -> int:
	if paddle != null and is_instance_valid(paddle):
		var pid = paddle.get("player_id")
		if pid != null:
			return 0 if int(pid) == 0 else 1
	return 0 if pos.x < ARENA_W * 0.5 else 1

func trigger_blast(charge_strength: float, pos: Vector2) -> void:
	var s := clampf(charge_strength, 0.4, 1.4) / 1.4
	_play2d("blast", "Blast", pos, lerpf(-9.0, -2.0, s), lerpf(0.92, 1.1, s), true, 2)

func trigger_super(pos: Vector2) -> void:
	_play2d("super", "Blast", pos, -1.0, 0.98, true, 1)
	_nudge_duck(3.0)

## Callers pass 1 for P1 on a goal; at match end game_manager also calls this with
## the match winner (0 = P1). The match_won signal handles that case, so a call
## right after a match stinger is dropped.
func trigger_goal(scorer_id: int, smash: bool) -> void:
	if Time.get_ticks_msec() - _match_stinger_ms < 300:
		return
	var key := "goal_p1" if scorer_id == 1 else "goal_p2"
	_play_stinger(key, -1.0, 1.04 if smash else 1.0)
	if smash:
		_play_stinger("goal_kenney", -12.0, 1.1)
	_nudge_duck(5.0)

func trigger_sting(freq: float, amp: float) -> void:
	var pitch := clampf(freq / 520.0, 0.65, 1.7)
	_play2d("sting", "World", Vector2(960.0, 540.0), lerpf(-18.0, -8.0, clampf(amp, 0.0, 1.0)), pitch, false, 2)

func trigger_stun(pos: Vector2) -> void:
	_play2d("stun", "Blast", pos, -3.0, 1.0, true, 2)

func trigger_stun_bolt(pos: Vector2) -> void:
	_play2d("stun_bolt_fire", "Blast", pos, -6.0, 1.0, true, 2)

func trigger_brick_hit(pos: Vector2) -> void:
	_play2d("brick_hit", "Impact", pos, -6.0, 1.0, true, 3)

func trigger_brick_shatter(pos: Vector2) -> void:
	_play2d("brick_shatter", "Impact", pos, -3.0, 1.0, true, 2)
	_play2d("brick_shard_tinkle", "Impact", pos, -9.0, 1.0, true, 2)

func trigger_blast_ready(pos: Vector2) -> void:
	_play2d("blast_ready", "World", pos, -8.0, 1.0, true, 2)

func trigger_powerup_spawn(pos: Vector2) -> void:
	_play2d("powerup_spawn", "World", pos, -7.0, 1.0, true, 1)

func trigger_powerup_collect(pos: Vector2) -> void:
	_play2d("powerup_collect", "World", pos, -4.0, 1.0, true, 2)

func trigger_powerup_expire() -> void:
	_play2d("powerup_expire", "World", Vector2(960.0, 540.0), -10.0, 1.0, false, 1)

func trigger_multiball(pos: Vector2) -> void:
	_play2d("multiball_split", "World", pos, -5.0, 1.0, true, 1)

func trigger_hazard(pos: Vector2) -> void:
	_play2d("hazard_vortex", "World", pos, -9.0, 1.0, true, 1)

func trigger_rally_tier(tier: int) -> void:
	var t := clampi(tier, 1, 4)
	_play_stinger("rally_tier_%d" % t, -9.0, 1.0)

func trigger_overdrive() -> void:
	_play_stinger("overdrive_riser", -4.0, 1.0)
	_nudge_duck(2.0)

func trigger_cymatic_lock(entered: bool) -> void:
	if entered and not _heart_on:
		_play_stinger("lock_enter", -3.0, 1.0)
		_nudge_duck(4.0)
	_heart_on = entered

func trigger_set_won(_winner: int) -> void:
	_play_stinger("set_won", -2.0, 1.0)
	_nudge_duck(4.0)

func trigger_match_won(_winner: int, human_won: bool) -> void:
	_match_stinger_ms = Time.get_ticks_msec()
	_pending_set_win = -1
	_play_stinger("match_won" if human_won else "match_lost", -1.0, 1.0)
	_lp_end = LP_MATCH_END
	_nudge_duck(6.0)

func trigger_stage_intro(stage: int) -> void:
	_lp_end = LP_OPEN
	_play_stinger("stage_intro", -3.0, clampf(1.0 - 0.02 * float(stage), 0.85, 1.05))
	_nudge_duck(4.0)

func trigger_stage_complete() -> void:
	_play_stinger("stage_complete", -3.0, 1.0)

func trigger_countdown_tick() -> void:
	_play_ui("countdown_tick", -6.0, 1.0)

func trigger_suck(active: bool, pos: Vector2, strength: float) -> void:
	var side := 0 if pos.x < ARENA_W * 0.5 else 1
	_suck_target[side] = clampf(strength, 0.0, 1.0) if active else 0.0
	if active and side < _suck.size():
		_suck[side].global_position = pos
		_suck[side].pitch_scale = lerpf(0.9, 1.1, clampf(strength, 0.0, 1.0))

func trigger_stream(active: bool, pos: Vector2, strength: float) -> void:
	var side := 0 if pos.x < ARENA_W * 0.5 else 1
	_stream_target[side] = clampf(strength, 0.0, 1.0) if active else 0.0
	if active and side < _stream.size():
		_stream[side].global_position = pos
		_stream[side].pitch_scale = lerpf(0.95, 1.12, clampf(strength, 0.0, 1.0))

# ============================================================ UI / meta triggers
func trigger_ui_navigate() -> void:
	_play_ui("ui_navigate", -8.0, randf_range(0.97, 1.03))

func trigger_ui_confirm() -> void:
	_play_ui("ui_confirm", -5.0, 1.0)

func trigger_ui_back() -> void:
	_play_ui("ui_back", -6.0, 1.0)

func trigger_menu_open() -> void:
	_play_ui("menu_open", -8.0, 1.0)
	_lp_end = LP_OPEN
	set_rally(0)

func trigger_pause(paused: bool) -> void:
	if paused == _paused:
		return
	_paused = paused
	_lp_pause = LP_PAUSE if paused else LP_OPEN
	_play_ui("pause" if paused else "resume", -6.0, 1.0)

## Legacy names used by menu_manager.
func trigger_ui_hover() -> void:
	trigger_ui_navigate()

func trigger_ui_click() -> void:
	trigger_ui_confirm()

func trigger_sandbox_tool() -> void:
	_play_ui("powerup_collect", -10.0, randf_range(1.1, 1.3))

# ============================================================ binding
## Connects to the existing gameplay signals so silent events get sound without
## touching the callers. Idempotent and null-safe; any argument may be null.
## tournament_mgr and chaos are untyped because they are created at runtime.
func bind_match(game_mgr: GameManager, ball: Ball, paddle_left: Paddle, paddle_right: Paddle, tournament_mgr = null, chaos = null) -> void:
	if game_mgr != null and is_instance_valid(game_mgr) and _mark_bound(game_mgr):
		_connect(game_mgr, "game_paused", _on_game_paused)
		_connect(game_mgr, "menu_entered", _on_menu_entered)
		_connect(game_mgr, "match_started", _on_match_started)
		_connect(game_mgr, "set_won", _on_set_won)
		_connect(game_mgr, "match_won", _on_match_won)
		_connect(game_mgr, "serving_started", _on_serving_started)
		_connect(game_mgr, "rally_updated", _on_rally_updated)
		_connect(game_mgr, "callout", _on_callout)
		# Phase 2 (signals may land later; _connect is has_signal-guarded).
		_connect(game_mgr, "serve_ready_beat", trigger_serve_beat)
		_connect(game_mgr, "serve_clock_warning", trigger_serve_warning)
		_connect(game_mgr, "auto_served", trigger_auto_served)
		_connect(game_mgr, "goal_theatre_started", trigger_goal_theatre)

	if ball != null and is_instance_valid(ball) and _mark_bound(ball):
		_bound_ball = ball
		_connect(ball, "overdrive_entered", trigger_overdrive)
		_connect(ball, "cymatic_lock_entered", _on_lock_entered)
		_connect(ball, "shattered", trigger_ball_shattered)

	for p in [paddle_left, paddle_right]:
		if p != null and is_instance_valid(p) and _mark_bound(p):
			_bound_paddles.append(p)
			_connect(p, "super_ready", _on_super_ready.bind(p))
			_connect(p, "stunned", _on_stunned.bind(p))
			_connect(p, "stun_fired", trigger_stun_bolt)
			_connect(p, "blast_charge_started", _on_blast_charge_started.bind(p))
			_connect(p, "blast_charge_released", _on_blast_charge_released.bind(p))
			_connect(p, "suck_captured", _on_suck_captured.bind(p))
			_connect(p, "slingshot_fired", _on_slingshot_fired.bind(p))
			_connect(p, "serve_aimed", trigger_serve_aimed)
	_bound_paddles = _bound_paddles.filter(func(x): return x != null and is_instance_valid(x))

	if tournament_mgr != null and is_instance_valid(tournament_mgr) and _mark_bound(tournament_mgr):
		_connect(tournament_mgr, "stage_started", _on_stage_started)
		_connect(tournament_mgr, "stage_completed", _on_stage_completed)

	if chaos != null and is_instance_valid(chaos) and _mark_bound(chaos):
		_connect(chaos, "powerup_collected", _on_powerup_collected)
		_connect(chaos, "multiball_started", _on_multiball_started)
		var host = chaos.get("host")
		if host != null and is_instance_valid(host):
			_connect(host, "child_entered_tree", _on_host_child_entered)
			var bricks = host.get("brick_matrix")
			if bricks != null and is_instance_valid(bricks) and _mark_bound(bricks):
				_connect(bricks, "brick_shattered", _on_brick_shattered)

func _mark_bound(obj: Object) -> bool:
	var id := obj.get_instance_id()
	if _bound.has(id):
		return false
	_bound[id] = true
	return true

func _connect(obj: Object, sig: String, callable: Callable) -> void:
	if obj == null or not obj.has_signal(sig):
		return
	if not obj.is_connected(sig, callable):
		obj.connect(sig, callable)

func _on_game_paused(is_paused: bool) -> void:
	trigger_pause(is_paused)

func _on_menu_entered() -> void:
	_paused = false
	_lp_pause = LP_OPEN
	_lp_theatre = LP_OPEN
	_theatre_t = 0.0
	for side in 2:
		_stop_charge(side)
		_orbit_t[side] = -1.0
	trigger_menu_open()
	set_soundtrack("hope")

func _on_match_started() -> void:
	_lp_end = LP_OPEN
	_lp_pause = LP_OPEN
	_lp_theatre = LP_OPEN
	_theatre_t = 0.0
	_paused = false
	set_rally(0)
	set_soundtrack("synth")
	if _music_on and _music_gain < 0.999:
		set_music_enabled(true)
		_music_fade_rate = 1.0 / MUSIC_FADE_IN

func _on_set_won(winner: int, sets_p1: int, sets_p2: int) -> void:
	if sets_p1 == 0 and sets_p2 == 0:
		return  # match reset emits set_won(0, 0, 0)
	_pending_set_win = winner
	_pending_set_ms = Time.get_ticks_msec()

func _on_match_won(winner: int) -> void:
	var human_won := true
	var w = null
	var l = null
	for p in _bound_paddles:
		if p == null or not is_instance_valid(p):
			continue
		if int(p.player_id) == winner:
			w = p
		else:
			l = p
	if w != null and bool(w.is_ai):
		human_won = l == null or bool(l.is_ai)  # AI vs AI counts as a neutral win
	trigger_match_won(winner, human_won)

func _on_serving_started(_server_id: int) -> void:
	trigger_countdown_tick()

func _on_rally_updated(hits: int) -> void:
	set_rally(hits)

func _on_callout(text: String, _color: Color) -> void:
	if text == "VORTEX" or text == "CURRENT":
		trigger_hazard(Vector2(960.0, 540.0))

func _on_lock_entered() -> void:
	trigger_cymatic_lock(true)

func _on_super_ready(p: Paddle) -> void:
	if p != null and is_instance_valid(p):
		trigger_blast_ready(p.global_position)

func _on_stunned(_duration: float, p: Paddle) -> void:
	if p != null and is_instance_valid(p):
		trigger_stun(p.global_position)

func _on_blast_charge_started(pos: Vector2, p: Paddle) -> void:
	trigger_blast_charge_started(pos, p)

func _on_blast_charge_released(pos: Vector2, power: float, p: Paddle) -> void:
	trigger_blast_charge_released(pos, power, p)

func _on_suck_captured(pos: Vector2, p: Paddle) -> void:
	trigger_suck_captured(pos, p)

func _on_slingshot_fired(pos: Vector2, speed: float, p: Paddle) -> void:
	trigger_slingshot(pos, speed, p)

func _on_stage_started(stage_index: int, _info: Dictionary) -> void:
	trigger_stage_intro(stage_index)

func _on_stage_completed(_stage_index: int, _info: Dictionary) -> void:
	trigger_stage_complete()

func _on_powerup_collected(_kind: int, owner_id: int) -> void:
	var pos := Vector2(480.0 if owner_id == 0 else 1440.0, 540.0)
	trigger_powerup_collect(pos)

func _on_multiball_started(_count: int) -> void:
	trigger_multiball(Vector2(960.0, 540.0))

func _on_host_child_entered(node: Node) -> void:
	if not (node is Powerup):
		return
	_on_powerup_added.call_deferred(node)

func _on_powerup_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	trigger_powerup_spawn((node as Node2D).global_position)
	var state := {"collected": false}
	if node.has_signal("collected"):
		node.connect("collected", func(_k, _h, _b): state["collected"] = true)
	node.tree_exited.connect(func():
		if not state["collected"] and is_inside_tree():
			trigger_powerup_expire()
	)

func _on_brick_shattered(_breaker_id: int, pos: Vector2) -> void:
	trigger_brick_shatter(pos)

# ============================================================ voice pool
func _nudge_duck(db: float) -> void:
	_duck = minf(_duck + db, 8.0)

func _play2d(key: String, bus: String, pos: Vector2, vol_db: float, pitch: float, humanise: bool, cap: int = DEFAULT_VOICE_CAP) -> AudioStreamPlayer2D:
	var stream := _next_variant(key)
	if stream == null or _pool.is_empty():
		return null
	if not _gate(key, cap):
		return null
	var chosen: AudioStreamPlayer2D = null
	for p in _pool:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _pool[_pool_i]
		_pool_i = (_pool_i + 1) % _pool.size()
		chosen.stop()
	_voice_key[chosen.get_instance_id()] = key
	chosen.bus = _bus(bus)
	chosen.stream = stream
	chosen.global_position = Vector2(clampf(pos.x, 0.0, ARENA_W), clampf(pos.y, 0.0, 1080.0))
	var g := vol_db
	var pt := pitch
	if humanise:
		g += randf_range(-GAIN_JITTER_DB, GAIN_JITTER_DB)
		pt *= 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)
	chosen.volume_db = g
	chosen.pitch_scale = clampf(pt, 0.55, 1.9)
	chosen.play()
	return chosen

func _play_stinger(key: String, vol_db: float, pitch: float) -> void:
	var stream := _next_variant(key)
	if stream == null or _stingers.is_empty():
		return
	if not _gate(key, 1):
		return
	var chosen: AudioStreamPlayer = null
	for p in _stingers:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _stingers[0]
		chosen.stop()
	_voice_key[chosen.get_instance_id()] = key
	chosen.stream = stream
	chosen.volume_db = vol_db
	chosen.pitch_scale = clampf(pitch, 0.55, 1.9)
	chosen.play()

func _play_ui(key: String, vol_db: float, pitch: float) -> void:
	var stream := _next_variant(key)
	if stream == null or _ui.is_empty():
		return
	if not _gate(key, 2):
		return
	var chosen: AudioStreamPlayer = null
	for p in _ui:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _ui[0]
		chosen.stop()
	_voice_key[chosen.get_instance_id()] = key
	chosen.stream = stream
	chosen.volume_db = vol_db
	chosen.pitch_scale = clampf(pitch, 0.55, 1.9)
	chosen.play()

## Per-stream minimum retrigger interval and voice cap.
func _gate(key: String, cap: int) -> bool:
	var now := Time.get_ticks_msec()
	var last: int = _last_play_ms.get(key, -100000)
	if now - last < RETRIGGER_MS:
		return false
	var active := 0
	for p in _pool:
		if p.playing and _voice_key.get(p.get_instance_id(), "") == key:
			active += 1
	for p in _stingers:
		if p.playing and _voice_key.get(p.get_instance_id(), "") == key:
			active += 1
	for p in _ui:
		if p.playing and _voice_key.get(p.get_instance_id(), "") == key:
			active += 1
	if active >= cap:
		return false
	_last_play_ms[key] = now
	return true

# ============================================================ resources
func _bus(name: String) -> String:
	return name if AudioServer.get_bus_index(name) >= 0 else "Master"

func _find_effect(bus: String, type) -> AudioEffect:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if is_instance_of(fx, type):
			return fx
	return null

func _variants(key: String) -> Array:
	if _lib.has(key):
		return _lib[key]
	var out: Array = []
	for rel in LIB.get(key, []):
		var s := _load_stream(SFX_DIR + rel)
		if s != null:
			if key in LOOP_KEYS:
				_set_loop(s, true)
			out.append(s)
	_lib[key] = out
	return out

func _next_variant(key: String) -> AudioStream:
	var v := _variants(key)
	if v.is_empty():
		return null
	if v.size() == 1:
		return v[0]
	var i: int = _rr.get(key, 0)
	# Round-robin with a random skip so patterns do not repeat audibly.
	var pick := (i + 1 + (randi() % (v.size() - 1))) % v.size()
	_rr[key] = pick
	return v[pick]

func _stream_for(key: String) -> AudioStream:
	var v := _variants(key)
	return v[0] if not v.is_empty() else null

func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		if not _missing.has(path):
			_missing[path] = true
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
		if on and wav.loop_end <= 0:
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate)) - 1
