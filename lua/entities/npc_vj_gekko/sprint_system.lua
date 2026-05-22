-- ============================================================
--  npc_vj_gekko / sprint_system.lua
--
--  Close-range sprint burst system.
--  Provides three globals called from init.lua:
--    GekkoSprint_Init(ent)
--    GekkoSprint_Think(ent, now)
--    GekkoSprint_End(ent)
-- ============================================================

if CLIENT then return end

-- ============================================================
-- TUNING  (must match the locals in init.lua)
-- ============================================================
local SPRINT_ENGAGE_DIST    = 1500
local SPRINT_DUR_MIN        = 2.0
local SPRINT_DUR_MAX        = 4.0
local SPRINT_COOLDOWN_MIN   = 4.0
local SPRINT_COOLDOWN_MAX   = 9.0
local SPRINT_MOVE_SPEED     = 420
local SPRINT_RUN_SPEED      = 420
local SPRINT_WALK_SPEED     = 420

-- ============================================================
function GekkoSprint_Init(ent)
    ent._gekkoSprinting    = false
    ent._sprintEndTime     = 0
    ent._sprintCooldownEnd = 0
end

-- ============================================================
function GekkoSprint_End(ent)
    if not IsValid(ent) then return end
    ent._gekkoSprinting = false
    -- Restore normal movement speeds
    ent:SetNWBool("GekkoSprinting", false)
end

-- ============================================================
function GekkoSprint_Think(ent, now)
    if not IsValid(ent) then return end

    -- If currently sprinting, check if the sprint window has expired
    if ent._gekkoSprinting then
        if now >= ent._sprintEndTime then
            GekkoSprint_End(ent)
            ent._sprintCooldownEnd = now + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
        end
        return
    end

    -- Cooldown gate
    if now < (ent._sprintCooldownEnd or 0) then return end

    -- Must have a valid living enemy close enough
    local enemy = ent:GetEnemy()
    if not IsValid(enemy) then return end
    if enemy:Health() <= 0 then return end

    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist > SPRINT_ENGAGE_DIST then return end

    -- Legs must be healthy
    if ent._gekkoLegsDisabled then return end

    -- Do not sprint while airborne
    if ent:GetNWInt("GekkoJumpState", 0) ~= 0 then return end

    -- Begin sprint
    ent._gekkoSprinting = true
    ent._sprintEndTime  = now + math.Rand(SPRINT_DUR_MIN, SPRINT_DUR_MAX)
    ent:SetNWBool("GekkoSprinting", true)
end
