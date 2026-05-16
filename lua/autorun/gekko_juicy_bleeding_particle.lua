-- ============================================================
-- FILE: lua/autorun/gekko_juicy_bleeding_particle.lua
-- PURPOSE: Particle precaching & ConVar registration
-- SCOPE: Shared (Autorun)
-- NOTE: Direct port of of_simple_bleeding_particle.lua with gekko_ namespace prefix
-- ============================================================

-- Register PCF archives containing the bleeding particle definitions
game.AddParticles("particles/gekko_juicy_bleeding.pcf")
game.AddParticles("particles/gekko_juicy_bleeding_darker.pcf")

-- Precache individual particle system names for runtime availability
PrecacheParticleSystem("gekko_juicy_bleeding_spray")
PrecacheParticleSystem("gekko_juicy_bleeding_spray_b")
PrecacheParticleSystem("gekko_juicy_bleeding_darker_spray")
PrecacheParticleSystem("gekko_juicy_bleeding_darker_spray_b")

-- ============================================================
-- CONSOLE VARIABLES (ConVars)
-- All identifiers prefixed with 'gekko_juicy_bleeding_' to prevent addon collisions
-- ============================================================

CreateConVar("gekko_juicy_bleeding_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")
CreateConVar("gekko_juicy_bleeding_player", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")
CreateConVar("gekko_juicy_bleeding_maxactive", "40", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "", 10, 500)
CreateConVar("gekko_juicy_bleeding_cooldown", "0.2", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "", 0, 1)
CreateConVar("gekko_juicy_bleeding_debug", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")
CreateConVar("gekko_juicy_bleeding_darker", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "")