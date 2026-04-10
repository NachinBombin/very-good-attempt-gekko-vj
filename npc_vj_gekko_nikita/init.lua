include("shared.lua")

-- ============================================================
--  npc_vj_gekko_nikita - full SNPC Nikita missile
--  Uses VJ aerial movement + nodegraph, no manual velocity hacks
-- ============================================================

-- Called when the SNPC is initialized
function ENT:CustomOnInitialize()
    self:SetModel("models/weapons/w_missile_launch.mdl")
    self:SetModelScale(7, 0)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-12, -12, -12), Vector(12, 12, 12))

    -- Lifetime / state
    self.Nikita_SpawnTime   = CurTime()
    self.Nikita_ExpireTime  = CurTime() + self.Nikita_LifeTime
    self.Nikita_Exploded    = false

    -- Make sure we do not try to melee or range attack
    self.HasMeleeAttack = false
    self.HasRangeAttack = false
end

-- Centralized explosion logic so we can call from think or death
function ENT:Nikita_DoExplosion(dmginfo)
    if self.Nikita_Exploded then return end
    self.Nikita_Exploded = true

    local pos   = self:GetPos()
    local dmg   = self.Nikita_Damage or 120
    local rad   = self.Nikita_Radius or 700
    local owner = IsValid(self.NikitaOwner) and self.NikitaOwner or self

    sound.Play("ambient/explosions/explode_8.wav", pos, 100, 100)
    util.ScreenShake(pos, 16, 200, 1, 3000)

    local ed = EffectData()
    ed:SetOrigin(pos)
    util.Effect("Explosion", ed)

    local pe = ents.Create("env_physexplosion")
    if IsValid(pe) then
        pe:SetPos(pos)
        pe:SetKeyValue("Magnitude",  tostring(math.floor(dmg * 5)))
        pe:SetKeyValue("radius",     tostring(rad))
        pe:SetKeyValue("spawnflags", "19")
        pe:Spawn(); pe:Activate()
        pe:Fire("Explode", "", 0)
        pe:Fire("Kill",    "", 0.5)
    end

    util.BlastDamage(self, owner, pos + Vector(0, 0, 50), rad, dmg)

    self:Remove()
end

-- VJ hook: called every think tick while AI is enabled
function ENT:CustomOnThink_AIEnabled()
    if self.Nikita_Exploded then return end

    -- Lifetime guard
    if self.Nikita_ExpireTime and CurTime() > self.Nikita_ExpireTime then
        self:Nikita_DoExplosion()
        return
    end

    -- Track enemy / target range only; let VJ Base decide movement
    local enemy = self:GetEnemy()
    if not IsValid(enemy) and IsValid(self.NikitaTargetEnt) then
        enemy = self.NikitaTargetEnt
        if enemy and enemy:IsValid() and self.VJ_DoSetEnemy then
            self:VJ_DoSetEnemy(enemy, true, true)
        elseif IsValid(enemy) then
            self:SetEnemy(enemy)
        end
    end

    if IsValid(enemy) then
        local dist = self:GetPos():Distance(enemy:GetPos())
        if dist <= (self.Nikita_ProxRadius or 220) then
            self:Nikita_DoExplosion()
            return
        end
    end
end

-- VJ hook: explode when killed by damage
function ENT:CustomOnKilled(dmginfo, hitgroup)
    self:Nikita_DoExplosion(dmginfo)
end
