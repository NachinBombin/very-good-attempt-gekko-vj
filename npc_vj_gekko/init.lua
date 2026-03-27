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

-- ============================================================
--  ANIMATION CALIBRATION
--  Tune ANIM_WALK_SPEED / ANIM_RUN_SPEED until arate~1.0 at
--  the NPC's natural cruise speed (read vel= from console).
-- ============================================================
local ANIM_WALK_SPEED    = 200
local ANIM_RUN_SPEED     = 200

-- Distance threshold: run engages above this, walk resumes below.
local RUN_ENGAGE_DIST    = 900
local RUN_DISENGAGE_DIST = 750   -- hysteresis to prevent flicker

-- MG burst config
local MG_ROUNDS    = 12
local MG_INTERVAL  = 0.1
local MG_DAMAGE    = 10
local MG_SPREAD    = 4

-- Weapon mode constants
local WMODE_MG      = 1
local WMODE_MISSILE = 2

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

function ENT:GekkoUpdateAnimation()
    if self.Flinching then return end

    -- GetAbsVelocity reflects the NPC's kinematic nav movement.
    -- GetVelocity() returns physics velocity which is 0 for AI-moved NPCs.
    local vel = self:GetAbsVelocity():Length()

    -- VJ Base stores the current enemy in self.Enemy, which is always
    -- valid during chase/combat. GetEnemy() may return NULL between schedules.
    local enemy = self.Enemy
    local dist  = IsValid(enemy) and self:GetPos():Distance(enemy:GetPos()) or 0

    -- Hysteresis: engage run above RUN_ENGAGE_DIST, drop back below RUN_DISENGAGE_DIST
    if dist > RUN_ENGAGE_DIST then
        self._gekkoRunning = true
    elseif dist < RUN_DISENGAGE_DIST then
        self._gekkoRunning = false
    end

    local targetSeq, arate

    if vel > 6 then
        if self._gekkoRunning then
            targetSeq = "run"
            arate     = vel / ANIM_RUN_SPEED
        else
            targetSeq = "walk"
            arate     = vel / ANIM_WALK_SPEED
        end
    else
        targetSeq = "idle"
        arate     = 1.0
    end

    if targetSeq ~= self.Gekko_LastSeqName then
        self:ResetSequence(targetSeq)
        self.Gekko_LastSeqName = targetSeq
    end

    self:SetPlaybackRate(arate)
    self:SetNWFloat("GekkoSpeed", vel)
    self:SetNWEntity("GekkoEnemy", IsValid(enemy) and enemy or NULL)
end

-- ============================================================
--  INIT
-- ============================================================
function ENT:Init()
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 256))
    self:SetSkin(1)

    self.GekkoSpineBone    = self:LookupBone("b_spine4")
    self.GekkoLGunBone     = self:LookupBone("b_l_gunrack")
    self.GekkoRGunBone     = self:LookupBone("b_r_gunrack")

    self.Gekko_NextDebugT  = 0
    self.Gekko_LastSeqName = ""
    self._missileCount     = 0
    self._mgBurstActive    = false
    self._weaponMode       = WMODE_MG
    self._gekkoRunning     = false

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
--  DAMAGE / KNOCKBACK SUPPRESSION
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    dmginfo:SetDamageForce(Vector(0, 0, 0))
    dmginfo:SetDamagePosition(self:GetPos())
    self.BaseClass.OnTakeDamage(self, dmginfo)
end

-- ============================================================
--  THINK
-- ============================================================
function ENT:OnThink()
    -- Sync physical move speed with run state
    if self._gekkoRunning then
        self.MoveSpeed = self.RunSpeed
    else
        self.MoveSpeed = self.WalkSpeed
    end

    self:GekkoUpdateAnimation()

    if CurTime() > self.Gekko_NextDebugT then
        local enemy = self.Enemy
        local dist  = IsValid(enemy) and math.floor(self:GetPos():Distance(enemy:GetPos())) or -1
        local vel   = self:GetAbsVelocity():Length()
        print(string.format(
            "[GekkoDBG] vel=%.1f  seq=%s  running=%s  enemyDist=%d",
            vel,
            tostring(self.Gekko_LastSeqName),
            tostring(self._gekkoRunning),
            dist
        ))
        self.Gekko_NextDebugT = CurTime() + 1
    end
end

-- ============================================================
--  RANGE ATTACK
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end

    local aimPos = enemy:GetPos() + Vector(0, 0, 40)

    local mode = self._weaponMode
    self._weaponMode = (mode == WMODE_MG) and WMODE_MISSILE or WMODE_MG

    -- ---- Machine Gun Burst ----
    if mode == WMODE_MG then
        if self._mgBurstActive then return true end
        self._mgBurstActive = true
        local entRef = self

        for i = 0, MG_ROUNDS - 1 do
            timer.Simple(i * MG_INTERVAL, function()
                if not IsValid(entRef) then return end

                local curEnemy = entRef.Enemy
                local curAim   = IsValid(curEnemy)
                    and (curEnemy:GetPos() + Vector(0, 0, 40))
                    or  aimPos

                local src
                local mgAtt = entRef:GetAttachment(ATT_MACHINEGUN)
                if mgAtt then
                    src = mgAtt.Pos
                else
                    local boneIdx = entRef.GekkoLGunBone
                    if boneIdx and boneIdx >= 0 then
                        local m = entRef:GetBoneMatrix(boneIdx)
                        if m then src = m:GetTranslation() + m:GetForward() * 28 end
                    end
                    src = src or (entRef:GetPos() + Vector(0, 0, 200))
                end

                local dir = (curAim - src):GetNormalized()

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

                local eff = EffectData()
                eff:SetOrigin(src)
                eff:SetNormal(dir)
                util.Effect("MuzzleFlash", eff)
                entRef:EmitSound("weapons/ar2/fire1.wav", 75, math.random(95, 115))

                if i == MG_ROUNDS - 1 then
                    entRef._mgBurstActive = false
                end
            end)
        end

        return true
    end

    -- ---- Missile ----
    self._missileCount = (self._missileCount or 0) + 1
    local missileAttIdx = (self._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R

    local misAtt = self:GetAttachment(missileAttIdx)
    local src
    if misAtt then
        src = misAtt.Pos
    else
        src = self:GetPos() + Vector(0, 0, 160)
    end
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

    local eff = EffectData()
    eff:SetOrigin(src)
    eff:SetNormal(dir)
    util.Effect("MuzzleFlash", eff)

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
