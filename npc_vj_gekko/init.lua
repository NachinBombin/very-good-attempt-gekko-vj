-- ============================================================
--  npc_vj_gekko / init.lua
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("crush_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")

util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")

local ATT_MACHINEGUN = 3
local ATT_MISSILE_L  = 9
local ATT_MISSILE_R  = 10

local ANIM_WALK_SPEED    = 184
local ANIM_RUN_SPEED     = 20
local RUN_ENGAGE_DIST    = 2300
local RUN_DISENGAGE_DIST = 1600
local RATE_SMOOTH_SPEED  = 8.0

local MG_ROUNDS_MIN = 11
local MG_ROUNDS_MAX = 36
local MG_INTERVAL   = 0.15
local MG_DAMAGE     = 25
local MG_SPREAD_MIN = 0.08
local MG_SPREAD_MAX = 0.8

local MG_SND_SHOTS       = { "gekko/shot.wav", "gekko/shot2.wav" }
local MG_SND_CHAININSERT = "gekko/chaininsert.wav"
local MG_CHAIN_EVERY     = 6
local MG_SND_LEVEL       = 95

local ROCKET_SND_FIRE = {
    "gekko/wp0040_se_gun_fire_01.wav",
    "gekko/wp0040_se_gun_fire_02.wav",
    "gekko/wp0040_se_gun_fire_03.wav",
}
local ROCKET_SND_LEVEL = 95

local TOPMISSILE_SND_FIRE = {
    "gekko/wp10e0_se_stinger_pass_1.wav",
    "gekko/wp0302_se_missile_fire_1.wav",
    "gekko/wp0302_se_missile_pass_2.wav",
}
local TOPMISSILE_SND_LEVEL = 95

local WWEIGHT_MG             = 35
local WWEIGHT_MISSILE_SINGLE = 20
local WWEIGHT_MISSILE_DOUBLE = 5
local WWEIGHT_GRENADE        = 10
local WWEIGHT_TOPMISSILE     = 10
local WWEIGHT_TRACKMISSILE   = 2
local WWEIGHT_ORBITRPG       = 10
local WWEIGHT_NIKITA         = 8

local SALVO_SPREAD_XY = 220
local SALVO_SPREAD_Z  = 80
local SALVO_DELAY     = 0.8

local GL_COUNT_MIN    = 4
local GL_COUNT_MAX    = 8
local GL_INTERVAL     = 0.35
local GL_SPREAD_Y     = 250
local GL_LAUNCH_Z     = 200
local GL_SOUND_FIDGET = "mac_bo2_m32/fidget.wav"
local GL_SOUND_FIRE   = "mac_bo2_m32/fire.wav"
local GL_SOUND_INSERT = "mac_bo2_m32/insert.wav"
local GL_FIDGET_LEAD  = 0.5
local GL_GRENADE_TYPES = { "bombin_gas_grenade", "ent_gas_stun", "ent_flashbang" }
local GL_TYPE_PARAMS = {
    ["bombin_gas_grenade"] = { speed = 2200, loft = 0.28 },
    ["ent_gas_stun"]       = { speed = 2750, loft = 0.35 },
    ["ent_flashbang"]      = { speed = 6500, loft = 0.42 },
}
local GL_TYPE_DEFAULT = { speed = 2650, loft = 0.35 }
local GL_TRAIL_MATERIAL  = "trails/smoke"
local GL_TRAIL_LIFETIME  = 0.6
local GL_TRAIL_STARTSIZE = 22
local GL_TRAIL_ENDSIZE   = 1
local GL_TRAIL_COLOR     = Color(235, 235, 235, 200)
local GL_MUZZLE_FLASH_SCALE = 0.4
local GL_SPARK_ATT_CYCLE = { ATT_MACHINEGUN, ATT_MISSILE_L, ATT_MISSILE_R }
local GL_SPARK_SCALE     = 0.5
local GL_SPARK_MAGNITUDE = 4
local GL_SPARK_RADIUS    = 10
local GL_VAPOR_EFFECT    = "SmokeEffect"
local GL_SMOKE_EFFECT    = "BlackSmoke"
local GL_VAPOR_SCALE     = 0.6
local GL_SMOKE_SCALE     = 0.4
local GL_SMOKE_EVERY     = 2

local KORNET_SND_SHOTS  = {
    "kornet/shot1.wav",
    "kornet/shot2.wav",
    "kornet/shot3.wav",
    "kornet/shot4.wav",
}
local KORNET_SND_LAUNCHES = { "kornet/launch1.wav", "kornet/launch2.wav" }
local KORNET_SND_LEVEL    = 95

local TOPMISSILE_LAUNCH_Z   = 300
local MISSILE_MIN_DIST      = 1200
local NIKITA_MIN_DIST       = 800
local MISSILE_SOUND_WARN    = "buttons/button17.wav"
local MISSILE_SPAWN_FORWARD = 600
local NIKITA_SPAWN_FORWARD  = 100
local NIKITA_SPAWN_Z        = 340

local NIKITA_MUZZLE_SMOKE_COUNT   = 5
local NIKITA_MUZZLE_SMOKE_SCALE   = 1.8
local NIKITA_MUZZLE_SMOKE_STAGGER = 0.06

local JUMP_STATE_NAMES       = { [0]="NONE", [1]="RISING", [2]="FALLING", [3]="LAND" }
local HEAD_Z_FRACTION        = 0.65
local BLOOD_DAMAGE_THRESHOLD = 900
local BLOOD_RANDOM_CHANCE    = 40
local GROUNDED_BLEED_CHANCE  = 0.85

local AERIAL_Z_THRESHOLD     = 450   -- FIX: was 4500 (unreachable); 450 matches a modest building height
local AERIAL_CHASE_INTERVAL  = 0.3
-- Interval between aerial weapon fires (VJ Base's own NextRangeAttackTime
-- governs ground cadence; this governs aerial-only intercept cadence).
local AERIAL_ATTACK_INTERVAL = 6.0
local AERIAL_EXIT_HYSTERESIS = 300

-- Watchdog polls this often; only un-sticks IsAbleToRangeAttack,
-- never zeros any timer (zeroing timers re-triggers VJ Base instantly).
local WATCHDOG_INTERVAL      = 3.0
-- How far past the attack deadline before watchdog intervenes.
local WATCHDOG_GRACE         = 8.0
