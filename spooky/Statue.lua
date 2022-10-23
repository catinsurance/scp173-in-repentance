local Statue = {}

local Enemy = Isaac.GetEntityTypeByName("Spooky Statue")
local SnapNeckSound = Isaac.GetSoundIdByName("NeckSnap")

local BLINK_INTERVAL = 30*9 -- how many frames between each blink
local CHARGEBAR_SPRITE = "gfx/chargebar.anm2"
local CHARGEBAR_FRAME_COUNT = 101
local CHARGEBAR_OFFSET_Y = 0.1 -- in scale, not pixels
local MOVE_PER_BLINK = 80
local SPEED = 6
local LOOK_ANGLE_LENIENCY = 0.3   -- how much the player can be off the angle before the statue charges at them

local DIRECTION_TO_VECTOR = {
    [Direction.LEFT] = Vector(-1, 0),
    [Direction.RIGHT] = Vector(1, 0),
    [Direction.UP] = Vector(0, -1),
    [Direction.DOWN] = Vector(0, 1),
}

local BAD_COLLISION_TYPES = {
    [GridCollisionClass.COLLISION_PIT] = true,
    [GridCollisionClass.COLLISION_WALL] = true,
    [GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER] = true,
    [GridCollisionClass.COLLISION_SOLID] = true,
}

local CurrentChargebar = nil
local CurrentCharge = nil
local BlinkSprite = nil
local CurrentRoomData

local function GetNearestPlayer(position)
    local nearestPlayer = nil
    local nearestDistance = nil

    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        local distance = (player.Position - position):Length()
        if nearestDistance == nil or distance < nearestDistance then
            nearestPlayer = player
            nearestDistance = distance
        end
    end

    return nearestPlayer
end

---@param pathfinder PathFinder
local function PathfindStep(pathfinder, currentPos, targetPos) -- returns the target position if its a clear line
    local line = Game():GetRoom():CheckLine(currentPos, targetPos, 0, 1)
    if line then -- we can just walk towards player
        return targetPos
    else
        pathfinder:FindGridPath(targetPos, 1, 4, true)
    end
end

local function VectorsAreEqual(vector1, vector2)
    return vector1.X == vector2.X and vector1.Y == vector2.Y
end

local function MakeChargeBar()
    local sprite = Sprite()
    sprite:Load(CHARGEBAR_SPRITE, true)
    sprite.Scale = Vector(2, 2)
    sprite.Color = Color(1, 1, 1, 0.5)
    return sprite
end

local function BlinkAnimation()
    local blink = Sprite()
    blink:Load("gfx/blink.anm2", true)
    blink:Play("Blink", true)
    blink.Scale = Vector(200, 200)
    BlinkSprite = blink
end

local function Blink()
    for _, statueEntity in ipairs(Isaac.FindByType(Enemy)) do
        local statue = statueEntity:ToNPC()
        statue.State = NpcState.STATE_ATTACK
    end

    BlinkAnimation()
end

local function Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

function Statue:RenderChargeBar()
    if CurrentChargebar and CurrentCharge and not Game():IsPaused() then
        if Game():GetRoom():IsClear() then
            CurrentChargebar = nil
            CurrentCharge = nil
            return
        end

        if CurrentCharge == 0 then -- its time to blink
            Blink()
            CurrentCharge = BLINK_INTERVAL
        else
            CurrentCharge = Clamp(CurrentCharge - 1, 0, BLINK_INTERVAL)
        end

        local frameAmountPerCharge = CurrentCharge / BLINK_INTERVAL
        local frame = Clamp(math.floor(CurrentCharge * frameAmountPerCharge), 1, CHARGEBAR_FRAME_COUNT)
        CurrentChargebar:SetFrame("Charging", frame)
        local yOffset = Isaac.GetScreenHeight() - (Isaac.GetScreenHeight() * CHARGEBAR_OFFSET_Y)
        CurrentChargebar:Render(Vector(Isaac.GetScreenWidth() / 2, yOffset))
    end

    if BlinkSprite then
        BlinkSprite:Update()
        BlinkSprite:Render(Vector(Isaac.GetScreenWidth() / 2, Isaac.GetScreenHeight() / 2), Vector(0, 0), Vector(0, 0))
        if BlinkSprite:IsFinished("Blink") then
            BlinkSprite = nil
        end
    end
end

function Statue:Init(enemy)
    if CurrentChargebar == nil then
        
        CurrentChargebar = MakeChargeBar()
        CurrentCharge = BLINK_INTERVAL
    end

    enemy:GetData().Statue = {}



    enemy.State = NpcState.STATE_IDLE
end

---@param statue EntityNPC
function Statue:Update(statue)

    -- check if all other enemies are dead

    local enemyExists = false
    ---@param entity Entity
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsVulnerableEnemy() and entity:IsActiveEnemy(false) then
            if entity.Type ~= Enemy then
                enemyExists = true
                break
            end     
        end
    end

    if not enemyExists then
        -- no other enemies, kill
        statue.State = NpcState.STATE_DEATH
        statue:Kill()
    end
    
    local data = statue:GetData().Statue
    if statue.State == NpcState.STATE_IDLE then -- statue is frozen
        statue.Velocity = Vector.Zero
    elseif statue.State == NpcState.STATE_MOVE then -- npc is running
        local target = data.Target
        if not target then
            target = GetNearestPlayer(statue.Position)
            data.Target = target
        end

        if target then -- safety check
            local moveTowards = PathfindStep(statue.Pathfinder, statue.Position, target.Position)

            if moveTowards then
                local moveVector = (moveTowards - statue.Position):Normalized() * SPEED
                statue.Velocity = moveVector
                
            end
        end
    elseif statue.State == NpcState.STATE_ATTACK then -- npc is blink teleporting
        local target = statue:GetPlayerTarget()

        local target = PathfindStep(statue.Pathfinder, statue.Position, target.Position)

        if target then
            local moveVector = (target - statue.Position):Normalized() * MOVE_PER_BLINK
            statue.Position = statue.Position + moveVector
            
        end
        statue.State = NpcState.STATE_IDLE
    end

    local lookingPlayer = nil
    local alivePlayersExist = false
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        

        if not player:IsDead() and player.HitPoints > 0 then
            alivePlayersExist = true
        end

        local headDirection = DIRECTION_TO_VECTOR[player:GetHeadDirection()] 
        local playerPos = player.Position
        local facing = (statue.Position - playerPos):Normalized():Dot(headDirection)
        if facing >= LOOK_ANGLE_LENIENCY then
            lookingPlayer = player
            break
        end
    end

    if not alivePlayersExist then
        statue.State = NpcState.STATE_IDLE
    elseif not lookingPlayer then
        statue.State = NpcState.STATE_MOVE
    else
        statue.State = NpcState.STATE_IDLE
    end
end

---@param npc EntityNPC
---@param collider Entity
function Statue:Collide(npc, collider)
    if npc.State ~= NpcState.STATE_ATTACK and npc.State ~= NpcState.STATE_MOVE then return end
    if not collider:IsDead() and collider.Type == EntityType.ENTITY_PLAYER then
        local player = collider:ToPlayer()
        
        SFXManager():Play(SnapNeckSound)
        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.LARGE_BLOOD_EXPLOSION, 0, player.Position, Vector.Zero, player)
        player:TakeDamage(1, 0, EntityRef(npc), player:GetDamageCooldown())

        -- teleport away to random location

        local room = Game():GetRoom()
        while true do
            local oldPos = npc.Position
            local randomPos = room:GetRandomPosition(0)
            randomPos = room:GetClampedPosition(randomPos, 0)
            if not BAD_COLLISION_TYPES[room:GetGridCollisionAtPos(randomPos)] then
                npc.Position = randomPos
                if npc.Pathfinder:HasPathToPos(player.Position, false) then
                    break
                else
                    npc.Position = oldPos -- set it back so there he isnt seen teleporting every frame
                end
            end
        end

        npc.State = NpcState.STATE_IDLE
    end
end

function Statue:Cleanup()
    CurrentChargebar = nil
    CurrentCharge = nil
    BlinkSprite = nil
end

return function (Mod)
    Mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, Statue.Init, Enemy)
    Mod:AddCallback(ModCallbacks.MC_POST_RENDER, Statue.RenderChargeBar)

    Mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, Statue.Update, Enemy)
    Mod:AddCallback(ModCallbacks.MC_PRE_NPC_COLLISION, Statue.Collide, Enemy)

    Mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Statue.Cleanup)
    Mod:AddCallback(ModCallbacks.MC_POST_GAME_END, Statue.Cleanup)
    Mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Statue.Cleanup)
    Mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Statue.Cleanup)
end