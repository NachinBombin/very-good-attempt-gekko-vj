-- ============================================================
--  npc_vj_gekko / elastic_system.lua  (v3 — fully standalone)
--
--  Weapon 10 : Elastic Tether
--  Range     : 0 – 900 units
--  Mechanic  : On fire, a visible rope is drawn between the
--              Gekko muzzle and the target.  Every server tick
--              a pull force is applied directly to the target's
--              physics object — no constraint.Elastic, no
--              toolgun, no AdvDupe2 dependency.
--
--  Visual rope: sent via net message each tick; drawn on the
--              client with a beam/rope effect (CurvedBeam).
--
--  Integration (already done in init.lua):
--    include("elastic_system.lua")
--    GekkoElastic_Init()     — in ENT:Init()
--    GekkoElastic_Think()    — in ENT:OnThink()
--    GekkoElastic_Fire(ent)  — called from FireElastic() local
--    GekkoElastic_OnRemove() — in ENT:OnDeath()
-- ============================================================

-- ── Net strings ──────────────────────────────────────────────
if SERVER then
    util.AddNetworkString("GekkoElasticRope")
    util.AddNetworkString("GekkoElasticSnap")
end

-- ── Tuning ───────────────────────────────────────────────────
local ELASTIC_MAX_DIST     = 900
local ELASTIC_DURATION     = 5.0      -- seconds the tether lasts
local ELASTIC_COOLDOWN_MIN = 14.0
local ELASTIC_COOLDOWN_MAX = 24.0

-- Force applied per tick toward the Gekko muzzle.
-- phys:ApplyForceCenter is in kg*in/s² (GMod units).
-- 280 000 gives a strong but survivable yank on a ~85 kg player.
local ELASTIC_FORCE        = 280000

-- How often (seconds) to re-apply force and re-send the rope net msg.
-- 0 = every single think tick (recommended for smooth pull).
local ELASTIC_TICK_RATE    = 0        -- every tick

-- Rope visuals (sent to client)
local ROPE_MATERIAL        = "cable/rope"
local ROPE_WIDTH           = 3        -- pixels
local ROPE_COLOR_R         = 40
local ROPE_COLOR_G         = 220
local ROPE_COLOR_B         = 80
local ROPE_COLOR_A         = 230
local ROPE_SEGMENTS        = 6        -- CurvedBeam subdivisions
local ROPE_NOISE           = 8        -- wobble amplitude

-- SFX
local SFX_FIRE             = "weapons/crossbow/bolt_fly1.wav"
local SFX_FIRE_LVL         = 90
local SFX_ATTACH           = "physics/metal/metal_solid_impact_hard1.wav"
local SFX_SNAP             = "physics/metal/metal_box_impact_hard1.wav"
local SFX_PULL_LOOP        = "ambient/energy/zap7.wav" -- short electric hum
local SFX_PULL_LOOP_LVL    = 65

-- ── Helpers ──────────────────────────────────────────────────

local function GetMuzzlePos(ent)
    local bone = ent.GekkoPelvisBone
    if bone and bone >= 0 then
        local m = ent:GetBoneMatrix(bone)
        if m then return m:GetTranslation() + Vector(0, 0, 200) end
    end
    return ent:GetPos() + Vector(0, 0, 200)
end

local function BroadcastSnap()
    net.Start("GekkoElasticSnap")
    net.Broadcast()
end

local function BroadcastRope(muzzle, targetPos)
    net.Start("GekkoElasticRope")
        net.WriteVector(muzzle)
        net.WriteVector(targetPos)
    net.Broadcast()
end

local function DestroyTether(ent, reason)
    if ent._elasticActive then
        BroadcastSnap()
        ent:EmitSound(SFX_SNAP, 80, math.random(90, 110), 1)
    end
    ent._elasticActive      = false
    ent._elasticTarget      = nil
    ent._elasticActiveUntil = 0
    ent._elasticLastTick    = 0
    print("[GekkoElastic] Tether removed — " .. (reason or "unknown"))
end

-- ── Init ─────────────────────────────────────────────────────

function ENT:GekkoElastic_Init()
    self._elasticActive      = false
    self._elasticTarget      = nil
    self._elasticActiveUntil = 0
    self._elasticLastTick    = 0
    self._elasticNextShotT   = CurTime() + math.Rand(ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)
    print("[GekkoElastic] Init")
end

-- ── Think (called every server tick from ENT:OnThink) ────────

function ENT:GekkoElastic_Think()
    if not self._elasticActive then return end

    local now = CurTime()

    -- Expiry
    if now >= self._elasticActiveUntil then
        DestroyTether(self, "expired")
        return
    end

    -- Target validity
    local target = self._elasticTarget
    if not IsValid(target) then
        DestroyTether(self, "target gone")
        return
    end

    -- Tick-rate gate
    if ELASTIC_TICK_RATE > 0 and (now - self._elasticLastTick) < ELASTIC_TICK_RATE then
        return
    end
    self._elasticLastTick = now

    local muzzle    = GetMuzzlePos(self)
    local targetPos = target:GetPos() + Vector(0, 0, 40)

    -- ── Apply pull force ─────────────────────────────────────
    local phys = target:GetPhysicsObject()
    if IsValid(phys) then
        local pullDir = (muzzle - targetPos):GetNormalized()
        phys:ApplyForceCenter(pullDir * ELASTIC_FORCE)
    elseif target:IsPlayer() then
        -- Players need SetVelocity nudge since their physobj may be invalid
        local pullDir = (muzzle - target:GetPos()):GetNormalized()
        local cur     = target:GetVelocity()
        target:SetVelocity(cur + pullDir * (ELASTIC_FORCE / 10000))
    end

    -- ── Send rope to all clients ──────────────────────────────
    BroadcastRope(muzzle, targetPos)
end

-- ── Fire ─────────────────────────────────────────────────────

function ENT:GekkoElastic_Fire(enemy)
    if self._elasticActive then
        print("[GekkoElastic] Already active")
        return false
    end

    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist > ELASTIC_MAX_DIST then
        print(string.format("[GekkoElastic] Too far (%.0f)", dist))
        return false
    end

    self._elasticActive      = true
    self._elasticTarget      = enemy
    self._elasticActiveUntil = CurTime() + ELASTIC_DURATION
    self._elasticLastTick    = 0
    self._elasticNextShotT   = CurTime() + math.Rand(ELASTIC_COOLDOWN_MIN, ELASTIC_COOLDOWN_MAX)

    -- SFX
    self:EmitSound(SFX_FIRE, SFX_FIRE_LVL, math.random(90, 110), 1)
    timer.Simple(0.1, function()
        if IsValid(enemy) then
            enemy:EmitSound(SFX_ATTACH, 80, math.random(85, 105), 1)
        end
    end)
    timer.Simple(0.2, function()
        if IsValid(self) and self._elasticActive then
            self:EmitSound(SFX_PULL_LOOP, SFX_PULL_LOOP_LVL, 100, 1)
        end
    end)

    print(string.format(
        "[GekkoElastic] FIRED | dist=%.0f  dur=%.1fs  force=%d",
        dist, ELASTIC_DURATION, ELASTIC_FORCE
    ))
    return true
end

-- ── Cleanup ──────────────────────────────────────────────────

function ENT:GekkoElastic_OnRemove()
    DestroyTether(self, "gekko removed")
end
