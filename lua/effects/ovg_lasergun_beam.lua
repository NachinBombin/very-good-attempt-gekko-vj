-- ============================================================
--  ovg_lasergun_beam.lua  (CLIENT)
--  Dual support: SWEP (player) + sent_lazer_turret entity
-- ============================================================

local _mat       = Material("sprites/physgbeamb")
local BEAM_W     = 2.5
local BEAM_COLOR = Color(0, 255, 255)
local BEAM_RANGE = 4096

function EFFECT:Init(data)
    self.Source     = data:GetEntity()
    self.Attachment = data:GetAttachment()
    self.IsSWEP     = false
    self.IsEntity   = false

    if IsValid(self.Source) then
        if self.Source:IsWeapon() then
            self.IsSWEP = true
        elseif self.Source:GetClass() == "sent_lazer_turret" then
            self.IsEntity = true
        end
    end
end

function EFFECT:Think()
    if not IsValid(self.Source) then return false end

    if self.IsSWEP then
        local ply = self.Source.Owner
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
        if ply:GetActiveWeapon() ~= self.Source then return false end
        local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * BEAM_RANGE, filter = ply })
        self:SetRenderBoundsWS(ply:GetShootPos(), tr.HitPos)
        return true
    end

    if self.IsEntity then
        if self.Source:GetNWBool("BLZT_Dead", false) then return false end
        if not self.Source:GetNWBool("BLZT_Firing", false) then return false end
        local fwd = self.Source:GetForward()
        local org = self.Source:GetPos() + fwd * 40 + Vector(0,0,10)
        local tr  = util.TraceLine({ start = org, endpos = org + fwd * BEAM_RANGE, filter = self.Source })
        self:SetRenderBoundsWS(org, tr.HitPos)
        return true
    end

    return false
end

function EFFECT:Render()
    if not IsValid(self.Source) then return end

    -- SWEP path
    if self.IsSWEP then
        local wep = self.Source
        local ply = wep.Owner
        if not IsValid(ply) then return end
        if wep:GetNWString("LaserState", "idle") ~= "firing" then return end
        local sp  = ply:GetShootPos()
        local tr  = util.TraceLine({ start = sp, endpos = sp + ply:GetAimVector() * BEAM_RANGE, filter = ply })
        render.SetMaterial(_mat)
        render.DrawBeam(self:GetTracerShootPos(sp, wep, self.Attachment), tr.HitPos, BEAM_W, 0, 1, wep.BeamColor or BEAM_COLOR)
        return
    end

    -- Entity (turret) path
    if self.IsEntity then
        local ent = self.Source
        if not ent:GetNWBool("BLZT_Firing", false) then return end
        if ent:GetNWBool("BLZT_Dead", false) then return end
        local fwd = ent:GetForward()
        local org = ent:GetPos() + fwd * 40 + Vector(0,0,10)
        local tr  = util.TraceLine({ start = org, endpos = org + fwd * BEAM_RANGE, filter = ent })
        render.SetMaterial(_mat)
        render.DrawBeam(org, tr.HitPos, ent.TURRET_BEAM_WIDTH or BEAM_W, 0, 1, ent.TURRET_BEAM_COLOR or BEAM_COLOR)
    end
end
