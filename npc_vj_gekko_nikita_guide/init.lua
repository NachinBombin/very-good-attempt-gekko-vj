AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Gekko Nikita path guide SNPC
-- Lightweight aerial helper that chases the enemy using VJ Base AI.

local spawnOffset = Vector(0, 0, 16)

function ENT:Init()
    -- Small hull so it fits through most interior spaces and doors
    self:SetCollisionBounds(Vector(16, 16, 16), Vector(-16, -16, -16))
    self:SetPos(self:GetPos() + spawnOffset)

    -- We do not want this guide to fight or make noise
    self.HasMeleeAttack = false
    self.HasRangeAttack = false
    self.HasLeapAttack  = false
    self.HasDeathCorpse = false

    -- If the spawner already chose an enemy for us, honour that
    local enemy = self:GetEnemy()
    if IsValid(enemy) and self.VJ_IsBeingControlled ~= true then
        -- Let VJ Base know it should actively chase this enemy
        if self.VJ_DoSetEnemy then
            self:VJ_DoSetEnemy(enemy, true, true)
        end
    end
end

function ENT:OnThink()
    -- If the linked missile is gone, quietly remove the guide to avoid
    -- leaving stray NPCs around the map.
    if self.NikitaMissile and (not IsValid(self.NikitaMissile) or self.NikitaMissile.Destroyed) then
        self:Remove()
        return
    end

    -- If we lost our enemy entirely, there is not much point in staying.
    local enemy = self:GetEnemy()
    if not IsValid(enemy) and self.VJ_IsBeingControlled ~= true then
        self:Remove()
        return
    end
end

function ENT:OnDeath(dmginfo, hitgroup, status)
    -- Do not spawn a corpse or extra effects; the missile handles the show.
    if status == "Init" then
        -- Returning true here tells VJ Base that we handled death visuals.
        return true
    end
end
