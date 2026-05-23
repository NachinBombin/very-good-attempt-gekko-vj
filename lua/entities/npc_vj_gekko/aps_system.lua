-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM  v2
--
-- Ported from nphalanx_aps (Current-Phalanx repo).
-- NPC differences vs. player Phalanx:
--   • Always active — no ON/OFF toggle
--   • Laser is OFF at all times (not player-operated)
--     Only lights up momentarily before firing (handled client-side
--     via GekkoAPSIntercept net msg — laser state bit = 1 for 80ms)
--   • Burst muzzle flash fires toward the intercept point via
--     the existing GekkoMuzzleFlash net message (preset 3)
--   • Full whitelist of every Gekko-owned munition class
--   • Gekko itself, other NPCs, fast ally NPCs, and players are
--     NEVER deleted — only hostile projectiles are intercepted
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_SCAN_RADIUS    = 1200    -- sphere radius around Gekko, units
local APS_MIN_SPEED      = 350     -- u/s — projectiles below this are ignored
local APS_SCAN_INTERVAL  = 0.05    -- seconds between threat scans
local APS_REARM_DELAY    = 0.30    -- cooldown between successive intercepts
local APS_BURST_SHOTS    = 4       -- muzzle flash pulses per intercept
local APS_BURST_INTERVAL = 0.040   -- seconds between burst pulses
local APS_HEADING_DOT    = 0.25    -- dot-product floor: threat must face Gekko

-- ============================================================
-- OWNED MUNITION WHITELIST
-- Every class Gekko itself fires is listed here.
-- These are NEVER intercepted regardless of speed or class name.
-- ============================================================
local APS_OWNED_CLASSES = {
    -- Missiles & rockets
    ["npc_vj_gekko_nikita"]   = true,   -- Nikita cruise missile
    ["sent_npc_topmissile"]   = true,   -- top-attack missile
    ["sent_npc_trackmissile"] = true,   -- active-track missile
    ["obj_vj_rocket"]         = true,   -- standard gekko rocket
    ["obj_gekko_rocket"]      = true,   -- alternate rocket entity name
    ["sent_orbital_rpg"]      = true,   -- orbital missile
    -- Bushmaster 25 mm cannon rounds
    ["sent_gekko_bushmaster"] = true,
    -- Grenade launcher payloads
    ["bombin_gas_grenade"]    = true,   -- toxic gas grenade
    ["ent_gas_stun"]          = true,   -- stun/gas grenade
    ["ent_flashbang"]         = true,   -- flash grenade
    -- Shell casings (physics debris — never a threat)
    ["prop_physics"]          = true,
    ["prop_dynamic"]          = true,
}

-- ============================================================
-- GLOBAL THREAT TABLE
-- Mirrors the Phalanx INTERCEPT_TARGETS list plus extras that
-- are relevant to threatening a large armoured NPC.
-- ============================================================
local APS_INTERCEPT_TARGETS = {
    ["rpg_missile"]               = true,
    ["grenade_ar2"]               = true,
    ["npc_grenade_frag"]          = true,
    ["prop_combine_ball"]         = true,
    ["hunter_flechette"]          = true,
    ["crossbow_bolt"]             = true,
    ["grenade_helicopter"]        = true,
    ["combine_mine"]              = true,
    ["npc_satchel"]               = true,
    ["satchel_charge"]            = true,
    ["npc_manhack"]               = true,
    ["obj_vj_grenade"]            = true,
    ["obj_vj_rocket"]             = false,  -- overridden by owned whitelist check first
    ["obj_vj_flechette"]          = true,
    ["sent_javelin_missile"]      = true,
    ["sent_stinger_missile"]      = true,
    ["neuro_missile"]             = true,
    ["neuro_rocket"]              = true,
    ["m9k_released_rpg"]          = true,
    ["m9k_davy_crockett_payload"] = true,
    ["m9k_40mm_grenade"]          = true,
    ["m9k_mad_grenade"]           = true,
    ["cw_grenade_thrown"]         = true,
    ["fas2_thrown_m67"]           = true,
    ["wac_hc_rocket"]             = true,
    ["lvs_missile"]               = true,
    ["lfs_missile"]               = true,
    ["lfs_rocket"]                = true,
    