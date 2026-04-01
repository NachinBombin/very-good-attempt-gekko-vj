-- ============================================================
--  sent_npc_topmissile / cl_init.lua
--  Client: exhaust particles + dynamic light while engine is live.
-- ============================================================
include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    if not self:GetNWBool("TMStarted") then return end

    if not self._emitter then
        self._emitter = ParticleEmitter(self:GetPos(), false)
    end
    if not self._emitter then return end

    local pos = self:GetPos() + self:GetForward() * -15
    local vel = self:GetForward() * -10

    -- Fire-core exhaust
    local p = self._emitter:Add("effects/smoke_a", pos)
    if p then
        p:SetVelocity(vel)
        p:SetDieTime(math.Rand(0.05, 0.1))
        p:SetStartAlpha(math.Rand(222, 255))
        p:SetEndAlpha(0)
        p:SetStartSize(math.random(4, 6))
        p:SetEndSize(math.random(20, 34))
        p:SetAirResistance(150)
        p:SetRoll(math.Rand(180, 480))
        p:SetRollDelta(math.Rand(-3, 3))
        p:SetColor(255, 100, 0)
    end

    -- Dynamic light
    local dl = DynamicLight(self:EntIndex())
    if dl then
        dl.Pos        = self:GetPos()
        dl.r          = 250 + math.random(-5, 5)
        dl.g          = 170 + math.random(-5, 5)
        dl.b          = 0
        dl.Brightness = 1
        dl.Decay      = 0.1
        dl.Size       = 2048
        dl.DieTime    = CurTime() + 0.15
    end
end

function ENT:OnRemove()
    if self._emitter then
        self._emitter:Finish()
        self._emitter = nil
    end
end
