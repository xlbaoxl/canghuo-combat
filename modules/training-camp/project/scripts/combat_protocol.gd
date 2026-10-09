extends RefCounted
## Stable vocabulary for the one executor used by gameplay, previews and AI.
const RULES = "dual-window-1.1"
const CONTENT = "training-dual-1.1"
const SAVE_SCHEMA = 4
const NORMAL = "NORMAL"
const OPPORTUNITY = "OPPORTUNITY"
const PHASES = ["INIT", "ENTRY_RESOLVE", "DISPATCH", "PUBLIC_TICK", "WINDOW_PRE", "WINDOW_OPEN", "DECISION", "ACTION_VALIDATE", "ACTION_COMMIT", "EFFECT_RESOLVE", "RESPONSE_DRAIN", "ACTION_CLOSE", "WINDOW_CLOSE", "BATTLE_END"]
const AUTO_EVENTS = ["BATTLE_ENTRY", "NORMAL_OPENED", "HP_DAMAGE_TAKEN", "PERIODIC_NET_HP_LOSS"]
const GAUGE_DEFAULTS = {"maximum":100, "passive_gain":2, "damage_weight":60, "guard_weight":0, "root_gain_cap":12, "combat_scale_ref":300}
const SERIES_BP = [0, 500, 1000]
const TECHNIQUE_BP = [0, 1000, 2000]
const STATS = ["H", "Hmax", "E", "M", "Q", "S", "P"]
const RESULT_FIELDS = {
	"damage":["base_request", "damage_request", "hp_loss", "shield_absorbed", "overkill"],
	"heal":["heal_request", "hp_restored", "heal_overflow"],
	"qi":["qi_request", "qi_restored", "qi_removed", "qi_overflow"],
	"apply":["layers_requested", "layers_added", "layers_before", "layers_after", "layers_overflow"],
	"remove":["layers_requested", "layers_removed", "layers_before", "layers_after"],
	"consume":["layers_requested", "layers_removed", "layers_before", "layers_after"]
}

static func whole(value, minimum:int=0, maximum:int=1000000)->bool:
	return (value is int or value is float) and is_finite(float(value)) and value==int(value) and value>=minimum and value<=maximum

static func round_ratio(a:int, b:int)->int:
	assert(a>=0 and b>0)
	return (2*a+b)/(2*b)

static func ceil_ratio(a:int, b:int)->int:
	assert(a>=0 and b>0)
	return (a+b-1)/b

static func isqrt_round(n:int)->int:
	var lo=0
	var hi=maxi(1,n)
	while lo<=hi:
		var m=(lo+hi)/2
		if m*m<=n:lo=m+1
		else:hi=m-1
	return hi+1 if 4*n>=(2*hi+1)*(2*hi+1) else hi
