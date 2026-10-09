extends RefCounted
## Easing for the Bonehead Labs splash: the site's CSS curves as functions of progress.
##
## The splash is a pure function of elapsed time (no tweens), so any instant can be posed and
## captured exactly. [method seg] slices the clock into per-element windows.


## One frame of sequence time, clamped so a stalled first frame cannot skip a beat.
static func step(delta: float) -> float:
	return clampf(delta, 0.0, 0.1)


## Progress of a window opening at [param start] and running for [param duration].
static func seg(t: float, start: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0 if t >= start else 0.0
	return clampf((t - start) / duration, 0.0, 1.0)


## CSS cubic-bezier(x1, y1, x2, y2) at progress [param x] (Newton, then bisection).
static func cubic_bezier(x: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var u: float = x
	for _i in range(8):
		var bx: float = _bez(u, x1, x2) - x
		if absf(bx) < 0.00001:
			return _bez(u, y1, y2)
		var d: float = _bez_slope(u, x1, x2)
		if absf(d) < 0.000001:
			break
		u -= bx / d
	var lo: float = 0.0
	var hi: float = 1.0
	u = x
	for _j in range(24):
		var bx2: float = _bez(u, x1, x2)
		if absf(bx2 - x) < 0.00001:
			break
		if bx2 < x:
			lo = u
		else:
			hi = u
		u = (lo + hi) * 0.5
	return _bez(u, y1, y2)


static func _bez(u: float, a: float, b: float) -> float:
	var v: float = 1.0 - u
	return 3.0 * v * v * u * a + 3.0 * v * u * u * b + u * u * u


static func _bez_slope(u: float, a: float, b: float) -> float:
	var v: float = 1.0 - u
	return 3.0 * v * v * a + 6.0 * v * u * (b - a) + 3.0 * u * u * (1.0 - b)


## The site's spring: cubic-bezier(.34, 1.56, .64, 1) (overshoots about 10%).
static func spring(x: float) -> float:
	return cubic_bezier(x, 0.34, 1.56, 0.64, 1.0)


## The site's out: cubic-bezier(.16, 1, .3, 1).
static func out(x: float) -> float:
	return cubic_bezier(x, 0.16, 1.0, 0.3, 1.0)


## The mascot jump's per-keyframe timing: cubic-bezier(.3, .7, .4, 1).
static func jump(x: float) -> float:
	return cubic_bezier(x, 0.3, 0.7, 0.4, 1.0)


## CSS ease-in-out: cubic-bezier(.42, 0, .58, 1).
static func in_out(x: float) -> float:
	return cubic_bezier(x, 0.42, 0.0, 0.58, 1.0)


static func in_cubic(x: float) -> float:
	return x * x * x


static func in_out_cubic(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5


static func in_out_sine(x: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(x, 0.0, 1.0))


static func out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
