-- ============================================================
-- npc_vj_gekko / impact_light_system.lua
-- SERVER-only.
--
-- Spawns a short-lived light_dynamic at the bullet/shell hit
-- position for two weapon types:
--
--   MG rounds  : every MG_LIGHT_EVERY rounds that actually
--                connect (EntityFireBullets, filtered to the
--                Gekko entity), warm orange flash, small range.
--
--   Bushmaster : every hit; brighter, wider, slightly longer
--                lived.  Called explicitly from init.lua via
--                GekkoImpactLight_Bushmaster( hitPos ).
--
-- The reference script this is based on used a global
-- EntityFireBullets hook with convars.  We avoid global
-- pollution by only reacting when the firing entity is a
-- Gekko NPC, and we skip convars since values are tuned
-- per-weapon here.
-- ============================================================
if CLIENT then return end

-- ============================================================
-- TUNABLES
-- ============================================================
local MG_LIGHT_EVERY    = 4        -- fire a light every N connected MG rounds
local MG_LIGHT_DIST     = 96       -- light_dynamic "distance" keyvalue (GMod units)
local MG_LIGHT_LIFE     = 0.08     -- seconds before Kill fire
local MG_LIGHT_R        = 255
local MG_LIGHT_G        = 165
local MG_LIGHT_B        = 60

local BM_LIGHT_DIST     = 220      -- Bushmaster 25mm: larger impact
local BM_LIGHT_LIFE     = 0.14
local BM_LIGHT_R        = 255
local BM_LIGHT_G        = 130
local BM_LIGHT_B        = 30

-- ============================================================
-- INTERNAL STATE
-- Per-entity MG hit counter table, keyed by entity index.
-- Cleaned up automatically when the Gekko is removed.
-- ============================================================
local _mgHitCount = {}

-- ============================================================
-- HELPERS
-- ============================================================
local function SpawnImpactLight( hitPos, dist, r, g, b, life )
    local lite = ents.Create("light_dynamic")
    if not IsValid(lite) then return end
    lite:SetKeyValue("distance", tostring(dist))
    lite:SetKeyValue("_light", r .. " " .. g .. " " .. b)
    lite:SetPos(hitPos)
    lite:Spawn()
    lite:Fire("Kill", "", life)
end

-- ============================================================
-- PUBLIC API
-- Called from init.lua FireBushmaster per shell hit.
-- ============================================================
function GekkoImpactLight_Bushmaster( hitPos )
    SpawnImpactLight(
        hitPos,
        BM_LIGHT_DIST, BM_LIGHT_R, BM_LIGHT_G, BM_LIGHT_B,
        BM_LIGHT_LIFE
    )
end

-- ============================================================
-- MG HIT LIGHT
-- Hooked into EntityFireBullets; fires only when the shooter
-- is a live npc_vj_gekko and the trace actually connects.
-- ============================================================
hook.Add("EntityFireBullets", "GekkoMG_ImpactLight", function( ent, bulletData )
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    local entIdx = ent:EntIndex()
    _mgHitCount[entIdx] = (_mgHitCount[entIdx] or 0) + 1
    if _mgHitCount[entIdx] < MG_LIGHT_EVERY then return end
    _mgHitCount[entIdx] = 0   -- reset counter

    -- Trace the exact bullet path to find the hit position.
    local tr = {}
    tr.start  = bulletData.Src
    tr.endpos = bulletData.Src + bulletData.Dir * 2147483647
    tr.filter = ent
    local result = util.TraceLine(tr)
    if not result.Hit then return end

    SpawnImpactLight(
        result.HitPos,
        MG_LIGHT_DIST, MG_LIGHT_R, MG_LIGHT_G, MG_LIGHT_B,
        MG_LIGHT_LIFE
    )
end)

-- Clean up the per-entity counter when the Gekko dies/is removed.
hook.Add("EntityRemoved", "GekkoMG_ImpactLight_Cleanup", function( ent )
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end
    _mgHitCount[ent:EntIndex()] = nil
end)
