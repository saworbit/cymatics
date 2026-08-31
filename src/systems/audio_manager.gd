class_name AudioManager
extends Node

## Procedural synth: drone bed + FM ball + punchy transients that climb with the rally.

@export var sample_rate := 48000
@export var buffer_length := 0.05

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback

var drone_cutoff := 120.0
var drone_resonance := 1.5
var bq_x1 := 0.0
var bq_x2 := 0.0
var bq_y1 := 0.0
var bq_y2 := 0.0
var brown_acc := 0.0

var ball_speed := 0.0
var ball_curl := 0.0
var ball_pan := 0.0
var phase_carrier := 0.0
var phase_mod := 0.0
var rally := 0

var paddle_grain_amp := 0.0
var paddle_grain_freq := 400.0
var paddle_grain_phase := 0.0

var impact_amp := 0.0
var impact_freq := 200.0
var impact_phase := 0.0
var impact_decay := 0.92
var noise_amp := 0.0

var sting_amp := 0.0
var sting_freq := 440.0
var sting_phase := 0.0

var chord_amp := 0.0
var chord_phase := Vector3.ZERO
var chord_freqs := Vector3(261.63, 329.63, 392.0)

var click_amp := 0.0
var heartbeat := 0.0
var heartbeat_phase := 0.0

func _ready() -> void:
	_init_synthesizer()

func _exit_tree() -> void:
	playback = null
	if player != null:
		player.stop()
		player.stream = null

func _init_synthesizer() -> void:
	player = AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = buffer_length
	player.stream = generator
	player.volume_db = -6.0
	add_child(player)
	player.play()
	playback = player.get_stream_playback()

func update_fluid_drone(avg_ke: float) -> void:
	var t := clampf(avg_ke / 4000.0, 0.0, 1.0)
	drone_cutoff = lerpf(80.0, 1600.0, t)
	drone_resonance = lerpf(1.15, 3.4, t)

func update_ball_state(speed: float, curl: float, norm_x: float) -> void:
	ball_speed = speed
	ball_curl = curl
	ball_pan = clampf(norm_x * 2.0 - 1.0, -1.0, 1.0)

func set_rally(hits: int) -> void:
	rally = hits
	if hits >= 11:
		heartbeat = 1.0
	elif hits >= 7:
		heartbeat = 0.45
	else:
		heartbeat = 0.0

func register_paddle_movement(speed: float, _norm_x: float) -> void:
	if speed > 60.0:
		paddle_grain_amp = minf(paddle_grain_amp + speed * 0.00012, 0.07)
		paddle_grain_freq = randf_range(250.0, 650.0) + speed * 0.3

func trigger_impact(impact_speed: float, _pos: Vector2, is_paddle: bool) -> void:
	var t := clampf(impact_speed / 1600.0, 0.0, 1.0)
	impact_amp = clampf(0.28 + t * 0.55, 0.25, 0.85)
	var rally_pitch := 1.0 + minf(rally * 0.045, 0.55)
	impact_freq = lerpf(140.0, 620.0, t) * rally_pitch
	impact_decay = 0.945 if is_paddle else 0.88
	noise_amp = 0.35 if is_paddle else 0.18
	click_amp = 0.4 if is_paddle else 0.12

func trigger_parry(_impact_speed: float, _pos: Vector2) -> void:
	impact_amp = 0.9
	impact_freq = 720.0
	impact_decay = 0.96
	noise_amp = 0.5
	click_amp = 0.85
	sting_amp = 0.55
	sting_freq = 1320.0

func trigger_blast(charge_strength: float, _pos: Vector2) -> void:
	impact_amp = 0.7 * charge_strength
	impact_freq = 180.0 * charge_strength
	impact_decay = 0.97
	noise_amp = 0.4

func trigger_super(_pos: Vector2) -> void:
	impact_amp = 1.0
	impact_freq = 90.0
	impact_decay = 0.985
	noise_amp = 0.7
	sting_amp = 0.7
	sting_freq = 220.0
	chord_amp = 0.45
	chord_freqs = Vector3(130.81, 196.0, 329.63)

func trigger_goal(scorer_id: int, smash: bool) -> void:
	chord_amp = 0.7 if smash else 0.5
	if scorer_id == 1:
		chord_freqs = Vector3(261.63, 329.63, 392.0)
	else:
		chord_freqs = Vector3(246.94, 311.13, 369.99)
	impact_amp = 0.8
	impact_freq = 70.0
	impact_decay = 0.98
	noise_amp = 0.35

func trigger_sting(freq: float, amp: float) -> void:
	sting_amp = amp
	sting_freq = freq

func _process(_delta: float) -> void:
	if playback == null:
		return
	var frames_available := playback.get_frames_available()
	if frames_available <= 0:
		return

	var TAU := 6.28318530718
	var w0 := TAU * drone_cutoff / float(sample_rate)
	var alpha := sin(w0) / (2.0 * drone_resonance)
	var b0 := alpha
	var b1 := 0.0
	var b2 := -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha

	var target_freq := lerpf(98.0, 740.0, clampf(ball_speed / 1600.0, 0.0, 1.0))
	target_freq *= 1.0 + minf(rally * 0.02, 0.28)
	var mod_index := absf(ball_curl) * 2.2

	var frames_to_generate := mini(frames_available, 1024)

	for f in range(frames_to_generate):
		var white := randf() * 2.0 - 1.0
		brown_acc = (brown_acc + 0.02 * white) / 1.02
		var drone_in := brown_acc * 3.2
		var drone_out := (b0 * drone_in + b1 * bq_x1 + b2 * bq_x2 - a1 * bq_y1 - a2 * bq_y2) / a0
		bq_x2 = bq_x1
		bq_x1 = drone_in
		bq_y2 = bq_y1
		bq_y1 = drone_out

		var mod_freq := target_freq * 0.5
		phase_mod += mod_freq * TAU / float(sample_rate)
		var mod_val := sin(phase_mod) * mod_index
		phase_carrier += (target_freq + mod_val) * TAU / float(sample_rate)
		var ball_sample := sin(phase_carrier) * (0.14 if ball_speed > 50.0 else 0.0)

		var grain_sample := 0.0
		if paddle_grain_amp > 0.0005:
			paddle_grain_phase += paddle_grain_freq * TAU / float(sample_rate)
			grain_sample = sin(paddle_grain_phase) * paddle_grain_amp
			paddle_grain_amp *= 0.9995

		var impact_sample := 0.0
		if impact_amp > 0.001:
			impact_phase += impact_freq * TAU / float(sample_rate)
			impact_freq = maxf(impact_freq * 0.9992, 36.0)
			impact_sample = sin(impact_phase) * impact_amp
			if noise_amp > 0.001:
				impact_sample += white * noise_amp * impact_amp
			impact_amp *= impact_decay
			noise_amp *= 0.992

		if click_amp > 0.001:
			impact_sample += white * click_amp
			click_amp *= 0.92

		var sting_sample := 0.0
		if sting_amp > 0.001:
			sting_phase += sting_freq * TAU / float(sample_rate)
			sting_sample = sin(sting_phase) * sting_amp
			sting_amp *= 0.9992
			sting_freq *= 0.99997

		var chord_sample := 0.0
		if chord_amp > 0.001:
			chord_phase.x += chord_freqs.x * TAU / float(sample_rate)
			chord_phase.y += chord_freqs.y * TAU / float(sample_rate)
			chord_phase.z += chord_freqs.z * TAU / float(sample_rate)
			chord_sample = (sin(chord_phase.x) + sin(chord_phase.y) * 0.7 + sin(chord_phase.z) * 0.5) * chord_amp * 0.33
			chord_amp *= 0.9996

		var hb := 0.0
		if heartbeat > 0.01:
			heartbeat_phase += 2.2 * TAU / float(sample_rate)
			hb = maxf(sin(heartbeat_phase), 0.0)
			hb = pow(hb, 8.0) * heartbeat * 0.18

		var ball_l := ball_sample * (1.0 - ball_pan) * 0.5
		var ball_r := ball_sample * (1.0 + ball_pan) * 0.5
		var left := drone_out * 0.16 + ball_l + grain_sample * 0.35 + impact_sample * 0.55 + sting_sample * 0.4 + chord_sample + hb
		var right := drone_out * 0.16 + ball_r + grain_sample * 0.35 + impact_sample * 0.55 + sting_sample * 0.4 + chord_sample + hb
		# Soft-knee saturation limiter
		left = left / (1.0 + absf(left) * 0.35)
		right = right / (1.0 + absf(right) * 0.35)
		playback.push_frame(Vector2(left, right))
