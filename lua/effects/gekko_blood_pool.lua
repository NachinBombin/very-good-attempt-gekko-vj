-- ============================================================
-- lua/effects/gekko_blood_pool.lua
-- Standalone blood pool for npc_vj_gekko.
-- Ported from call_of_duty_modern_warfare_2019_blood_pools_mod.
-- No external addon or PCF particle dependencies.
--
-- Triggered by: sv_gekko_bloodpool.lua (server) +
--               cl_gekko_bloodpool.lua (client)
-- ============================================================

-- Base HL2/GMod textures — circular blood splash, flat on floor.
local POOL_TEXTURES = {
    "particle/blood1",
    "particle/blood2",
    "particle/blood3",
    "particle/blood4",
}

-- Tuning (Gekko is large so pools are bigger than human-scale)
local POOL_MIN_SIZE = 50   -- radius units
local POOL_MAX_SIZE = 90
local POOL_LIFETIME = 120  -- seconds before pool disappears

-- ── HELPERS ──────────────────────────────────────────────────

local function IsSolid(pos)
    return bit.band(util.PointContents(pos), CONTENTS_SOLID) == CONTENTS_SOLID
end

-- Walk outward in 8 directions and verify floor exists at every step.
-- Returns the maximum radius that won't float in the air.
local function GetMaximumPoolSize(pos, limit)
    local fraction = 1
    local dn_dist  = 4

    for size = 1, limit, fraction do
        local d = size
        local spots = {
            pos + Vector( 0,  d,  0),
            pos + Vector( d,  0,  0),
            pos + Vector( d,  d,  0),
            pos + Vector( d, -d,  0),
            pos + Vector( 0, -d,  0),
            pos + Vector(-d, -d,  0),
            pos + Vector(-d,  0,  0),
            pos + Vector(-d,  d,  0),
        }

        for i = 1, #spots do
            local spos = spots[i] + Vector(0, 0,  1)
            local epos = spots[i] + Vector(0, 0, -dn_dist)

            if not IsSolid(spos) then
                local tr = util.TraceLine({ start = spos, endpos = epos, mask = MASK_DEADSOLID })
                if not tr.Hit then
                    return (size - fraction)
                end
            end
        end
    end

    return limit
end

-- ── EFFECT ───────────────────────────────────────────────────

function EFFECT:Init(data)
    local ent = data:GetEntity()
    if not IsValid(ent) then return end

    self.Entity   = ent
    self.BoneID   = data:GetAttachment() or 0
    self.LifeTime = CurTime() + POOL_LIFETIME

    -- Wait for the ragdoll to settle before placing the pool.
    self.BloodTime    = CurTime() + math.Rand(2, 5)
    self.MaxBloodTime = CurTime() + 20

    self.Initialized = true
end

function EFFECT:Think()
    if not self.Initialized then return true end

    -- Clean up when entity gone or lifetime expired.
    if not IsValid(self.Entity) or self.LifeTime < CurTime() then
        if self.BloodPool then
            self.BloodPool:SetLifeTime(0)
            self.BloodPool:SetDieTime(0.05)
            self.BloodPool:SetStartSize(0)
            self.BloodPool:SetEndSize(0)
        end
        if IsValid(self.Emitter) then
            self.Emitter:SetNoDraw(true)
            self.Emitter:Finish()
        end
        return false
    end

    local ent = self.Entity

    local bonePos = ent:GetBonePosition(self.BoneID)
    if not bonePos then return true end

    if not self.BloodPool then
        -- Lazily create emitter at bone position.
        if not IsValid(self.Emitter) then
            self.Emitter = ParticleEmitter(bonePos, true)
        end

        if CurTime() >= self.BloodTime and CurTime() < self.MaxBloodTime then
            -- Check physics velocity of the bone's physics object.
            local physBone = ent:TranslateBoneToPhysBone(self.BoneID)
            local phys     = physBone and ent:GetPhysicsObjectNum(physBone)
            local speed    = (phys and phys:IsValid()) and phys:GetVelocity():LengthSqr() or 0

            if speed < 10 then
                -- Trace down from the bone to find the floor.
                local tr = util.TraceLine({
                    start  = bonePos + Vector(0, 0,  32),
                    endpos = bonePos + Vector(0, 0, -128),
                    mask   = MASK_DEADSOLID,
                })

                if tr.Hit then
                    local floorPos = tr.HitPos + tr.HitNormal * 0.1
                    local limit    = math.random(POOL_MIN_SIZE, POOL_MAX_SIZE)
                    local size     = GetMaximumPoolSize(floorPos, limit)

                    if size > 5 then
                        local ang  = tr.HitNormal:Angle()
                        ang.roll   = math.random(0, 360)

                        local maxtime = (size / 50) * 10

                        local p = self.Emitter:Add(table.Random(POOL_TEXTURES), floorPos)
                        if p then
                            p:SetPos(floorPos)
                            p:SetAngles(ang)
                            p:SetStartSize(size * 0.5)
                            p:SetEndSize(size * 4.0)
                            p:SetDieTime(maxtime * 1.2)
                            p:SetStartAlpha(0)
                            p:SetEndAlpha(200)
                            p:SetVelocity(Vector(0, 0, 0))
                            p:SetGravity(Vector(0, 0, 0))

                            self.BloodPool      = p
                            self.StartBleedTime = CurTime()
                            self.PoolMaxTime    = maxtime
                        else
                            -- Texture add failed, retry after a pause.
                            self.BloodTime = CurTime() + 1
                        end
                    else
                        -- Not enough floor support, retry.
                        self.BloodTime = CurTime() + 1
                    end
                end
            end
        end
    else
        -- Pool particle exists: keep it alive each Think tick.
        if IsValid(self.Emitter) then
            self.Emitter:Finish()
            self.Emitter = nil
        end
        local elapsed = CurTime() - self.StartBleedTime
        self.BloodPool:SetLifeTime(math.min(elapsed, self.PoolMaxTime))
    end

    return true
end

function EFFECT:Render() end
