include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

local ATT_MACHINEGUN  = 3
local ATT_MISSILE_L   = 9
local ATT_MISSILE_R   = 10

local ANIM_WALK_SPEED = 170
local ANIM_RUN_SPEED  = 280

-- ============================================================
--  ANIMATION
--  VJ Base drives sequence selection via AnimTbl_* in shared.lua.
--  We only override playback rate here to sync leg speed to velocity.
--  TranslateActivity is NOT overridden: returning raw sequence indices
--  from it conflicts with VJ's internal ACT resolution.
-- ============================================================
function ENT:GekkoGetSpeed()
    local pos = self:GetPos()
    local dt  = FrameTime()
    if not self._lastPos or dt <= 0 then
        self._lastPos = pos
        return self._smoothSpd or 0
    end
    local spd   = (pos - self._lastPos):Length() / dt
    self._lastPos = pos
    local alpha = 1 - math.exp(-dt * 12)
    self._smoothSpd = self._smoothSpd + (spd - self._smoothSpd) * alpha
    return self._smoothSpd
end

function ENT:GekkoUpdateAnimation()
    if self.AttackAnimTime and CurTime() < self.AttackAnimTime then return end
    if self.Flinching then return end

    local vel = self:GekkoGetSpeed()
    local arate

    if vel > 160 then
        arate = vel / ANIM_RUN_SPEED
    elseif vel > 6 then
        arate = vel / ANIM_WALK_SPEED
    else
        arate = 0.08
    end

    self:SetPlaybackRate(arate)
    self:SetPoseParameter("move_x", math.Clamp(arate, 0, 1))
    self:SetNWFloat("GekkoSpeed", vel)

    local enemy = self:GetEnemy()
    self:SetNWEntity("GekkoEnemy", IsValid(enemy) and enemy or NULL)
end

-- ============================================================
--  INIT
-- ============================================================
function ENT:Init()
    -- Collision bounds scaled to the model's actual visual footprint.
    -- HULL_LARGE navmesh cell is ~50 units; bounds match that.
    -- Height ~200 covers the torso; legs extend below origin.
    self:SetCollisionBounds(Vector(-50, -50, 0), Vector(50, 50, 200))
    self:SetSkin(1)

    self.GekkoSpineBone    = self:LookupBone("b_spine4")
    self.GekkoLGunBone     = self:LookupBone("b_l_gunrack")
    self.GekkoRGunBone     = self:LookupBone("b_r_gunrack")
    self.Gekko_LastSeqName = ""
    self._lastPos          = self:GetPos()
    self._smoothSpd        = 0

    print(string.format(
        "[GekkoNPC] Init  Spine4=%d  LGun=%d  RGun=%d",
        self.GekkoSpineBone or -1,
        self.GekkoLGunBone  or -1,
        self.GekkoRGunBone  or -1
    ))
    print(string.format(
        "[GekkoNPC] Attachments  MG=%s  MissileL=%s  MissileR=%s",
        self:GetAttachment(ATT_MACHINEGUN) and "OK" or "MISSING",
        self:GetAttachment(ATT_MISSILE_L)  and "OK" or "MISSING",
        self:GetAttachment(ATT_MISSILE_R)  and "OK" or "MISSING"
    ))
end

-- ============================================================
--  THINK
-- ============================================================
function ENT:OnThink()
    self:GekkoUpdateAnimation()
end

-- ============================================================
--  MELEE
-- ============================================================
function ENT:OnMeleeAttackExecute(status, enemy)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end

    local stompDuration = 1.4
    self:SetNWFloat("GekkoStompEnd", CurTime() + stompDuration)

    timer.Simple(stompDuration * 0.5, function()
        if not IsValid(self) or not IsValid(enemy) then return end
        if self:GetPos():Distance(enemy:GetPos()) > 160 then return end
        local dmg = DamageInfo()
        dmg:SetAttacker(self)
        dmg:SetInflictor(self)
        dmg:SetDamage(85)
        dmg:SetDamageType(DMG_CLUB)
        dmg:SetDamagePosition(enemy:GetPos())
        enemy:TakeDamageInfo(dmg)
        self:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 100, 80)
    end)

    return true
end

-- ============================================================
--  RANGE ATTACK
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end

    local aimPos   = enemy:GetPos() + Vector(0, 0, 40)
    local firedAny = false

    self._missileToggle = not self._missileToggle
    local missileAttIdx = self._missileToggle and ATT_MISSILE_L or ATT_MISSILE_R

    -- Machine gun from attachment 3
    local mgAtt = self:GetAttachment(ATT_MACHINEGUN)
    if mgAtt then
        local src = mgAtt.Pos
        local dir = (aimPos - src):GetNormalized()
        self:FireBullets({
            Attacker=self, Damage=8, Dir=dir, Src=src,
            AmmoType="AR2", TracerName="Tracer", Num=3, Spread=Vector(0.04,0.04,0)
        })
        local eff = EffectData()
        eff:SetOrigin(src) eff:SetNormal(dir)
        util.Effect("MuzzleFlash", eff)
        firedAny = true
    else
        local m = self.GekkoLGunBone and self.GekkoLGunBone >= 0 and self:GetBoneMatrix(self.GekkoLGunBone)
        if m then
            local src = m:GetTranslation() + m:GetForward() * 28
            local dir = (aimPos - src):GetNormalized()
            self:FireBullets({ Attacker=self, Damage=8, Dir=dir, Src=src, AmmoType="AR2", TracerName="Tracer", Num=3, Spread=Vector(0.04,0.04,0) })
            local eff = EffectData() eff:SetOrigin(src) eff:SetNormal(dir) util.Effect("MuzzleFlash", eff)
            firedAny = true
        end
    end

    -- Missile from alternating launcher attachment
    local misAtt = self:GetAttachment(missileAttIdx)
    if misAtt then
        local src = misAtt.Pos
        local dir = (aimPos - src):GetNormalized()
        local rocket = ents.Create("obj_vj_rocket")
        if IsValid(rocket) then
            rocket:SetPos(src)
            rocket:SetAngles(dir:Angle())
            rocket:SetOwner(self)
            rocket:Spawn()
            rocket:Activate()
            local phys = rocket:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1200) end
        end
        local eff = EffectData() eff:SetOrigin(src) eff:SetNormal(dir) util.Effect("MuzzleFlash", eff)
        firedAny = true
    end

    if not firedAny then
        local src = self:GetPos() + Vector(0, 0, 200)
        self:FireBullets({ Attacker=self, Damage=8, Dir=(aimPos-src):GetNormalized(), Src=src, AmmoType="AR2", TracerName="Tracer", Num=3, Spread=Vector(0.05,0.05,0) })
    end

    self:EmitSound("weapons/ar2/fire1.wav", 80, math.random(90, 110))
    return true
end

-- ============================================================
--  DEATH
-- ============================================================
function ENT:OnDeath(dmginfo, hitgroup, status)
    if status ~= "Finish" then return end
    local attacker = IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker() or self
    local pos      = self:GetPos()
    timer.Simple(0.8, function()
        if not IsValid(self) then return end
        ParticleEffect("astw2_nightfire_explosion_generic", pos, angle_zero)
        self:EmitSound(VJ.PICK({"weapons/mgs3/explosion_01.wav", "weapons/mgs3/explosion_02.wav"}), 511, 100, 2)
        util.BlastDamage(self, attacker, pos, 512, 256)
    end)
end
