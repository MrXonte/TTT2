---
-- @class ENT
-- @section ttt_smokegrenade_proj

if SERVER then
    AddCSLuaFile()
end

DEFINE_BASECLASS("ttt_basegrenade_proj")

ENT.Type = "anim"
ENT.Base = "ttt_basegrenade_proj"
ENT.Model = Model("models/weapons/w_eq_smokegrenade_thrown.mdl")
ENT.SmokeLifetime = 15
ENT.ExtinguishInterval = 0.25
ENT.FlameLifetimeReduction = 1
ENT.VFireLifetimeReduction = 5

AccessorFunc(ENT, "radius", "Radius", FORCE_NUMBER)

if SERVER then
    local mathMax = math.max
    local entsFindInSphere = ents.FindInSphere

    local function ReduceTTTFlameLife(flame, amount)
        local dieTime = flame:GetDieTime()

        if dieTime == 0 then
            return
        end

        flame:SetDieTime(mathMax(CurTime(), dieTime - amount))
    end

    local function SoftenVFireOnEntity(ent, amount)
        if not vFireInstalled or not isfunction(vFireGetFires) then
            return
        end

        local fires = vFireGetFires(ent)

        if not fires then
            return
        end

        for _, fire in pairs(fires) do
            if IsValid(fire) and isfunction(fire.SoftExtinguish) then
                fire:SoftExtinguish(amount)
            end
        end
    end

    ---
    -- @param boolean extinguishNow
    -- @realm server
    function ENT:SuppressFires(extinguishNow)
        local entsInSphere = entsFindInSphere(self:GetPos(), self:GetRadius())
        local vFireLifeReduction = extinguishNow
            and self.VFireLifetimeReduction * 2
            or self.VFireLifetimeReduction

        for i = 1, #entsInSphere do
            local ent = entsInSphere[i]

            if not IsValid(ent) or ent == self then
                continue
            end

            if ent:GetClass() == "ttt_flame" then
                if extinguishNow then
                    ent:SetDieTime(0)
                else
                    ReduceTTTFlameLife(ent, self.FlameLifetimeReduction)
                end

                continue
            end

            if vFireInstalled and isfunction(ent.SoftExtinguish) then
                ent:SoftExtinguish(vFireLifeReduction)
            end

            SoftenVFireOnEntity(ent, vFireLifeReduction)

            if ent:IsOnFire() then
                ent:Extinguish()
            end
        end
    end
end

---
-- @ignore
function ENT:Initialize()
    if not self:GetRadius() then
        self:SetRadius(20)
    end

    return BaseClass.Initialize(self)
end

---
-- @ignore
function ENT:Think()
    if not self.hasDetonated then
        return BaseClass.Think(self)
    end

    if CLIENT then
        return
    end

    if self.smokeEndTime <= CurTime() then
        self:Remove()

        return
    end

    if self.nextExtinguishTick <= CurTime() then
        self:SuppressFires(false)
        self.nextExtinguishTick = CurTime() + self.ExtinguishInterval
    end

    self:NextThink(CurTime())

    return true
end

if CLIENT then
    local smokeparticles = {
        Model("particle/particle_smokegrenade"),
        Model("particle/particle_noisesphere"),
    }

    ---
    -- @ignore
    function ENT:CreateSmoke(center)
        local em = ParticleEmitter(center)

        local r = self:GetRadius()
        for i = 1, 20 do
            local prpos = VectorRand() * r
            prpos.z = prpos.z + 32
            local p = em:Add(table.Random(smokeparticles), center + prpos)
            if p then
                local gray = math.random(75, 200)
                p:SetColor(gray, gray, gray)
                p:SetStartAlpha(255)
                p:SetEndAlpha(200)
                p:SetVelocity(VectorRand() * math.Rand(900, 1300))
                p:SetLifeTime(0)

                p:SetDieTime(math.Rand(50, 70))

                p:SetStartSize(math.random(140, 150))
                p:SetEndSize(math.random(1, 40))
                p:SetRoll(math.random(-180, 180))
                p:SetRollDelta(math.Rand(-0.1, 0.1))
                p:SetAirResistance(600)

                p:SetCollide(true)
                p:SetBounce(0.4)

                p:SetLighting(false)
            end
        end

        em:Finish()
    end
end

---
-- @ignore
function ENT:Explode(tr)
    if SERVER then
        self:SetDetonateExact(0)
        self:SetNoDraw(true)
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)

        -- pull out of the surface
        if tr.Fraction ~= 1.0 then
            self:SetPos(tr.HitPos + tr.HitNormal * 0.6)
        end

        self.hasDetonated = true
        self.smokeEndTime = CurTime() + self.SmokeLifetime
        self.nextExtinguishTick = 0

        self:SuppressFires(true)
    else
        local spos = self:GetPos()
        util.PaintDown(spos, "SmallScorch", self)

        self:SetDetonateExact(0)

        if tr.Fraction ~= 1.0 then
            spos = tr.HitPos + tr.HitNormal * 0.6
        end

        -- Smoke particles can't get cleaned up when a round restarts, so prevent
        -- them from existing post-round.
        if gameloop.GetRoundState() == ROUND_POST then
            return
        end

        self:CreateSmoke(spos)
    end
end
