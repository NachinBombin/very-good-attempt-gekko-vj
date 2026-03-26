include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

-- ============================================================
--  ATTACHMENT INDICES
--  att 3  = machine gun barrel  (b_l_gunrack region)
--  att 9  = left  rocket launcher barrel  (b_l_hand region)
--  att 10 = right rocket launcher barrel  (b_r_hand region)
-- ============================================================
local ATT_MACHINEGUN   = 3
local ATT_MISSILE_L    = 9
local ATT_MISSILE_R    = 10

local ANIM_WALK_SPEED  = 170
local ANIM_RUN_SPEED   = 280

-- MG burst config
local MG_ROUNDS        = 12      -- bullets per attack call
local MG_INTERVAL      = 0.1    -- seconds between each round
local MG_DAMAGE        = 10
local MG_SPREAD        = 4  -- cone half-angle in radians (tighter than before)

-- ============================================================
--  ANIMATION
-- ============================================================
function ENT:SetAnimationTranslations(wepHoldType)
    local walkSeq = self:LookupSequence("walk")
    local runSeq  = self:LookupSequence("run")
    local idleSeq = self:LookupSequence("idle")

    self.AnimationTranslations[ACT_IDLE]     = idleSeq
    self.AnimationTranslations[ACT_WALK]     = walkSeq
    self.AnimationTranslations[ACT_RUN]      = runSeq
    self.AnimationTranslations[ACT_WALK_AIM] = walkSeq
    self.AnimationTranslations[ACT_RUN_AIM]  = runSeq

    self.GekkoSeq_Walk = walkSeq
    self.GekkoSeq_Run  = runSeq
    self.GekkoSeq_Idle = idleSeq

    print(string.format("[GekkoNPC] AnimTrans  idle->%d  walk->%d  run->%d", idleSeq, walkSeq, runSeq))
end

function ENT:TranslateActivity(act)
    if act == ACT_WALK or act == ACT_WALK_AIM then
        return self.GekkoSeq_Walk or act
    elseif act == ACT_RUN or act == ACT_RUN_AIM then
        return self.GekkoSeq_Run or act
    elseif act == ACT_IDLE then
        return self.GekkoSeq_Idle or act
    end
    return self.BaseClass.TranslateActivity(self, act)
end

function ENT:GekkoGetSpeed()
    local pos = self:GetPos()
    local dt  = FrameTime()

    if not self._lastPos or dt <= 0 then
        self._lastPos = pos
        return self._smoothSpd or 0
    end

    local spd = (pos - self._lastPos):Length() / dt
    self._lastPos = pos

    local alpha = 1 - math.exp(-dt * 12)
    self._smoothSpd = self._smoothSpd + (spd - self._smoothSpd) * alpha

    return self._smoothSpd
end

function ENT:GekkoUpdateAnimation()
    if self.AttackAnimTime and CurTime() < self.AttackAnimTime then return end
    if self.Flinching then return end

    local vel = self:GekkoGetSpeed()

    local targetSeq, arate
    if vel > 160 then
        targetSeq = "run"
        arate     = vel / ANIM_RUN_SPEED
    elseif vel > 6 then
        targetSeq = "walk"
        arate     = vel / ANIM_WALK_SPEED
    else
        targetSeq = "idle"
        arate     = 0.08
    end

    if targetSeq ~= self.Gekko_LastSeqName then
        self:ResetSequence(targetSeq)
        self.Gekko_LastSeqName = targetSeq
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
    self:SetCollisionBounds(Vector(-36, -36, 0), Vector(36, 36, 96))
    self:SetSkin(1)

    self.GekkoSpineBone    = self:LookupBone("b_spine4")
    self.GekkoLGunBone     = self:LookupBone("b_l_gunrack")
    self.GekkoRGunBone     = self:LookupBone("b_r_gunrack")

    self.Gekko_NextDebugT  = 0
    self.Gekko_LastSeqName = ""
    self._lastPos          = self:GetPos()
    self._smoothSpd        = 0
    self._missileCount     = 0   -- counts missile shots; even = L, odd = R
    self._mgBurstActive    = false

    -- ---- Physics: make the Gekko very heavy so it doesn't float/fly ----
    -- VJ creature base entities are not physical by default, but if a
    -- physics object exists (e.g. from a prop model), pin it down.
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(50000)
        phys:EnableMotion(false)   -- lock physics entirely; nav system moves us
    end

    -- Sanity-check attachments at spawn
    local mgAtt   = self:GetAttachment(ATT_MACHINEGUN)
    local misLAtt = self:GetAttachment(ATT_MISSILE_L)
    local misRAtt = self:GetAttachment(ATT_MISSILE_R)
    print(string.format(
        "[GekkoNPC] Init  Spine4=%d  LGun=%d  RGun=%d",
        self.GekkoSpineBone, self.GekkoLGunBone, self.GekkoRGunBone
    ))
    print(string.format(
        "[GekkoNPC] Attachments  MG=%s  MissileL=%s  MissileR=%s",
        mgAtt   and "OK" or "MISSING",
        misLAtt and "OK" or "MISSING",
        misRAtt and "OK" or "MISSING"
    ))
end

-- ============================================================
--  KNOCKBACK SUPPRESSION
--  SNPCs are not physics objects but bullet force and explosions
--  can still displace them via the engine. We absorb that here.
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    -- Zero out any velocity imparted by the damage source.
    -- We do this every hit; it has no effect on health (VJ handles that).
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0, 0, 0))
        phys:SetAngularVelocity(Vector(0, 0, 0))
    end
    -- Also clamp entity velocity directly (works even without a physobj)
    self:SetLocalVelocity(Vector(0, 0, 0))
end

-- ============================================================
--  THINK
-- ============================================================
function ENT:OnThink()
    self:GekkoUpdateAnimation()

    if CurTime() > self.Gekko_NextDebugT then
        local enemy = self:GetEnemy()
        local dist  = IsValid(enemy) and math.floor(self:GetPos():Distance(enemy:GetPos())) or -1
        local atkT  = self.AttackAnimTime and string.format("%.2f", self.AttackAnimTime - CurTime()) or "n/a"
        print(string.format(
            "[GekkoDBG] smoothSpd=%.1f  seq=%s  act=%d  moving=%s  enemyDist=%d  atkRemain=%s",
            self._smoothSpd or 0,
            tostring(self.Gekko_LastSeqName),
            self:GetActivity(),
            tostring(self:IsMoving()),
            dist,
            atkT
        ))
        self.Gekko_NextDebugT = CurTime() + 1
    end
end


--  RANGE ATTACK
--
--  MACHINE GUN  — sequential burst: MG_ROUNDS shots, MG_INTERVAL apart.
--                 Each shot = 1 bullet with individual random spread,
--                 giving a proper spray pattern over time.
--                 Fires from att 3; falls back to b_l_gunrack bone.
--
--  MISSILES     — strictly alternating L / R per OnRangeAttackExecute call.
--                 Uses _missileCount (incremented each call) so the toggle
--                 is never reset accidentally by the MG logic.
--                 Fires from att 9 (L) or att 10 (R).
--
--  NOTE: VJ Base's RangeAttackProjectiles ("obj_vj_rocket" in shared.lua)
--  is intentionally NOT used here — we manage missiles manually so we can
--  control which attachment fires. Set RangeAttackProjectiles = false in
--  shared.lua to prevent VJ from double-firing a second rocket.
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end

    local aimPos = enemy:GetPos() + Vector(0, 0, 40)

    -- ---- Sequential Machine Gun Burst ----
    if not self._mgBurstActive then
        self._mgBurstActive = true
        local entRef = self  -- capture for timer closures

        for i = 0, MG_ROUNDS - 1 do
            timer.Simple(i * MG_INTERVAL, function()
                if not IsValid(entRef) then return end

                -- Re-resolve enemy position each shot for accurate leading
                local curEnemy = entRef:GetEnemy()
                local curAim   = IsValid(curEnemy)
                    and (curEnemy:GetPos() + Vector(0, 0, 40))
                    or  aimPos

                local src, dir

                local mgAtt = entRef:GetAttachment(ATT_MACHINEGUN)
                if mgAtt then
                    src = mgAtt.Pos
                else
                    local boneIdx = entRef.GekkoLGunBone
                    if boneIdx and boneIdx >= 0 then
                        local m = entRef:GetBoneMatrix(boneIdx)
                        if m then
                            src = m:GetTranslation() + m:GetForward() * 28
                        end
                    end
                    src = src or (entRef:GetPos() + Vector(0, 0, 200))
                end

                dir = (curAim - src):GetNormalized()

                -- Individual bullet: 1 round, unique random spread per shot
                entRef:FireBullets({
                    Attacker   = entRef,
                    Damage     = MG_DAMAGE,
                    Dir        = dir,
                    Src        = src,
                    AmmoType   = "AR2",
                    TracerName = "Tracer",
                    Num        = 1,
                    Spread     = Vector(
                        (math.random() - 0.5) * 2 * MG_SPREAD,
                        (math.random() - 0.5) * 2 * MG_SPREAD,
                        0
                    ),
                })

                -- Muzzle flash + sound every shot
                local eff = EffectData()
                eff:SetOrigin(src)
                eff:SetNormal(dir)
                util.Effect("MuzzleFlash", eff)
                entRef:EmitSound("weapons/ar2/fire1.wav", 75, math.random(95, 115))

                -- Clear burst flag after last shot
                if i == MG_ROUNDS - 1 then
                    entRef._mgBurstActive = false
                end
            end)
        end
    end

    -- ---- Alternating Missile ----
    -- _missileCount starts at 0. Even = fire Left, Odd = fire Right.
    self._missileCount = (self._missileCount or 0) + 1
    local missileAttIdx = (self._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R

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
            if IsValid(phys) then
                phys:SetVelocity(dir * 1200)
            end
        end

        local eff = EffectData()
        eff:SetOrigin(src)
        eff:SetNormal(dir)
        util.Effect("MuzzleFlash", eff)
    else
        -- Fallback: fire from body center if attachment missing
        local src = self:GetPos() + Vector(0, 0, 160)
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
    end

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