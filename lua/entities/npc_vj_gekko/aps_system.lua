-- ============================================================
-- npc_vj_gekko / aps_system.lua
-- GEKKO ACTIVE PROTECTION SYSTEM
--
-- Adapted from nphalanx_aps logic (Current-Phalanx repo).
-- Differences from the player-placed Phalanx:
--   • Always active on the NPC — no ON/OFF toggle
--   • Laser beam draw is DISABLED (NPC, not player-operated)
--   • Muzzle flash burst fires toward the intercept point
--     using the existing GekkoMuzzleFlash net message
--   • Whitelist covers all of Gekko's own munitions
--   • Gekko itself and other NPCs / players are never deleted
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING
-- ============================================================
local APS_SCAN_RADIUS    = 1200   -- units
local APS_MIN_SPEED      = 350    -- u/s  (lower than Phalanx – picks up slower rockets)
local APS_SCAN_INTERVAL  = 0.05   -- seconds between scans
local APS_REARM_DELAY    = 0.35   -- seconds between successive intercepts
local APS_BURST_SHOTS    = 3      -- muzzle flash pulses per intercept
local APS_BURST_INTERVAL = 0.045  -- seconds between each burst pulse
local APS_HEADING_DOT    = 0.30   -- minimum dot-product (threat must be heading toward Gekko)

-- ============================================================
-- OWNED MUNITION WHITELIST
-- These classes are NEVER intercepted regardless of speed.
-- ============================================================
local APS_OWNED_CLASSES = {
    ["npc_vj_gekko_nikita"]   = true,
    ["sent_npc_topmissile"]   = true,
    ["sent_npc_trackmissile"] = true,
    ["sent_gekko_bushmaster"] = true,
    ["obj_vj_rocket"]         = true,
    ["sent_orbital_rpg"]      = true,
    ["bombin_gas_grenade"]    = true,
    ["ent_gas_stun"]          = true,
    ["ent_flashbang"]         = true,
    -- shell casings spawned by Gekko
    ["prop_physics"]          = true,
    ["prop_dynamic"]          = true,
}

-- ============================================================
-- INTERCEPT TARGET CLASS LIST  (from Phalanx + Gekko threats)
-- ============================================================
local APS_INTERCEPT_TARGETS = {
    ["rpg_missile"]               = true,
    ["grenade_ar2"]               = true,
    ["npc_grenade_frag"]          = true,
    ["prop_combine_ball"]         = true,
    ["hunter_flechette"]          = true,
    ["crossb