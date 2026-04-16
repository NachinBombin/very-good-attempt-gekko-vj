ENT.Type      = "anim"
ENT.Base      = "base_anim"
ENT.PrintName = "Gekko 25mm Round"
ENT.Author    = "Gekko"
ENT.Spawnable = false

function ENT:SetBirthTime(v) self:SetNWFloat("BirthTime", v) end
function ENT:GetBirthTime()  return self:GetNWFloat("BirthTime", 0) end
function ENT:SetSpawnPos(v)  self:SetNWVector("SpawnPos", v) end
function ENT:GetSpawnPos()   return self:GetNWVector("SpawnPos", Vector(0,0,0)) end
function ENT:SetSpawnDir(v)  self:SetNWVector("SpawnDir", v) end
function ENT:GetSpawnDir()   return self:GetNWVector("SpawnDir", Vector(1,0,0)) end
