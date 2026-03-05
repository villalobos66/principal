local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

-- Variables principales
local CarnageEnabled = false
local ESPEnabled = false
local originalSizes = {}
local collectConnection = nil
local espConnection = nil
local lastAttackTime = 0
local targetPlayer = nil          -- Jugador específico (si se escribió un nombre)
local targetPlayerName = ""
local exactTargetName = ""

-- Variables para Headsit permanente (SENTADO REAL)
local headsitActive = false
local headsitConnection = nil
local currentHeadsitTarget = nil   -- Objetivo actual del headsit

-- ============ CONFIGURACIÓN DE ZONA ============
local ZONE_CONFIG = {
    POSICION = Vector3.new(-1896, 33.5, -70),
    TAMANO = Vector3.new(68, 26, 115),
    COLOR = Color3.fromRGB(255, 0, 0),
    TRANSPARENCIA = 1, -- Cubo invisible, solo bordes visibles
}
local limiteMin = ZONE_CONFIG.POSICION - ZONE_CONFIG.TAMANO/2
local limiteMax = ZONE_CONFIG.POSICION + ZONE_CONFIG.TAMANO/2
local targetEnZona = false
local zoneCheckInterval = 0.1 -- Verificar cada 0.1 segundos para detección INSTANTÁNEA
local rangoVisual = nil
local posicionRingBaja = ZONE_CONFIG.POSICION - Vector3.new(0, ZONE_CONFIG.TAMANO.Y/2 - 2, 0) -- Centro, parte BAJA del ring

-- Variables para control de estabilidad y detección de bugs
local ultimaPosicionTarget = nil
local ultimaDistancia = nil
local teleportCount = 0
local lastTeleportTime = 0

-- Variables globales para ESP
_G.FriendColor = Color3.fromRGB(0, 0, 255)
_G.EnemyColor = Color3.fromRGB(255, 0, 0)
_G.UseTeamColor = true

-- Holder para ESP
local Holder

-- Almacenar conexiones por jugador
local playerConnections = {}

-- Lista de usuarios prohibidos
local PROHIBITED_USERS = {
    "Crxsyx", 
	"LaCoquette6_2", 
	"dewn_sz", 
	"KayKayRirisangel", 
	"Sianq", 
    "nadmire_JL", 
	"Fyro_190", 
	"Msky_nlh", 
	"Zdiogobreno042", 
	"diogobreno0421",
    "Ikaris_BR", 
	"rosado289", 
	"grancheroka_br", 
	"tokyo",
	"xxdeidaraxx50",
	"ShingekiNoKyojin_17", 
	"Gatitblox", 
	"mmelii_rdz",
	"darkissoez",
	"darkissoez1",
	"darkissoez2",
	"darkissoez3",
	"darkissoez4",
	"darkissoez5",
	"darkissoez6",
	"darkissoez7",
	"darkissoez8",
	"darkissoez9",
	"darkissoez10",
	"darkissoez11",
	"darkissoez12",
	"darkissoez13",
	"darkissoez14",
	"darkissoez15",
	"darkissoez16",
	"darkissoez17",
	"botfuerte1",
	"botfuerte2",
	"botfuerte3",
	"botfuerte4",
	"botfuerte5",
	"botfuerte6",
	"botfuerte7",
	"botfuerte8",
	"botfuerte9",
	"botfuerte10",
	"botfuerte11",
	"botfuerte12",
	"botfuerte13",
	"botfuerte14",
	"bloodalt2020",
	"crxsyx121"
	}

-- Configuración - ALCANCE E HITBOX TRIPLICADOS con 2000 ataques/segundo
local attacksPerSecond = 1000
local attackCooldown = 1 / attacksPerSecond
local AURA_RANGE = 225
local HITBOX_SIZE = Vector3.new(540, 540, 540)

-- Remote para ataques
local HitRemote = game:GetService("ReplicatedStorage")
    :WaitForChild("Packages")
    :WaitForChild("Knit")
    :WaitForChild("Services")
    :WaitForChild("CombatService")
    :WaitForChild("RF")
    :WaitForChild("Hit")

-- ==================== ANTI-RAGDOLL ULTRA (INTEGRADO) ====================
local AntiRagdollEnabled = false
local antiRagdollHeartbeat = nil
local antiRagdollCharConnection = nil

-- Almacén para objetos modificados (para restaurarlos al desactivar)
local modifiedObjects = {
    constraints = {},
    animations = {},
    scripts = {},
    parts = {},
}

-- Función para restaurar todo
local function restoreAll()
    local char = player.Character
    if not char then return end
    
    pcall(function()
        -- 1. Restaurar constraints
        for _, constraint in ipairs(modifiedObjects.constraints) do
            if constraint and constraint.Parent then
                pcall(function()
                    if constraint:IsA("Constraint") and constraint:FindFirstChild("Enabled") then
                        constraint.Enabled = true
                    elseif constraint:IsA("Constraint") then
                        if constraint.Parent ~= char then
                            constraint.Parent = char
                        end
                    end
                end)
            end
        end
        
        -- 2. Restaurar animaciones (reproducir las que estaban activas)
        for _, animTrack in ipairs(modifiedObjects.animations) do
            pcall(function()
                if animTrack and animTrack.Parent then
                    animTrack:Play()
                end
            end)
        end
        
        -- 3. Restaurar scripts (habilitar si es posible)
        for _, scriptObj in ipairs(modifiedObjects.scripts) do
            pcall(function()
                if scriptObj and scriptObj.Parent then
                    if scriptObj:IsA("Script") then
                        scriptObj.Disabled = false
                    elseif scriptObj:IsA("LocalScript") then
                        -- No se puede re-habilitar, pero ya se movió de vuelta
                    end
                end
            end)
        end
        
        -- 4. Restaurar partes movidas
        for _, partData in ipairs(modifiedObjects.parts) do
            pcall(function()
                if partData.part and partData.part.Parent ~= char then
                    partData.part.Parent = char
                    if partData.anchored ~= nil then
                        partData.part.Anchored = partData.anchored
                    end
                end
            end)
        end
        
        -- 5. Restaurar estado del humanoide (solo si no hay headsit activo)
        local hum = char:FindFirstChild("Humanoid")
        if hum and not headsitActive then
            hum.PlatformStand = false
            hum.AutoRotate = true
        end
        
        -- Limpiar el almacén
        modifiedObjects.constraints = {}
        modifiedObjects.animations = {}
        modifiedObjects.scripts = {}
        modifiedObjects.parts = {}
    end)
    
    print("🔄 Anti-Ragdoll: protecciones revertidas")
end

-- Función para aplicar protecciones (se ejecuta en cada frame)
local function applyAntiRagdollProtections()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    
    pcall(function()
        -- 1. Forzar estado del humanoide (evitar ragdoll)
        local badStates = {
            [Enum.HumanoidStateType.Physics] = true,
            [Enum.HumanoidStateType.FallingDown] = true,
            [Enum.HumanoidStateType.GettingUp] = true,
            [Enum.HumanoidStateType.Dead] = true,
        }
        if badStates[hum:GetState()] then
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end

        -- 2. Desactivar PlatformStand solo si NO estamos en headsit
        if not headsitActive then
            hum.PlatformStand = false
            hum.AutoRotate = true
        end

        -- 3. Desactivar constraints (sin destruir)
        for _, constraint in ipairs(char:GetDescendants()) do
            if constraint:IsA("Constraint") then
                -- Guardar referencia si no está ya guardada
                local alreadySaved = false
                for _, saved in ipairs(modifiedObjects.constraints) do
                    if saved == constraint then alreadySaved = true break end
                end
                if not alreadySaved then
                    table.insert(modifiedObjects.constraints, constraint)
                end
                
                if constraint:FindFirstChild("Enabled") then
                    constraint.Enabled = false
                else
                    local tempFolder = player:FindFirstChild("TempAntiRagdoll") 
                    if not tempFolder then
                        tempFolder = Instance.new("Folder")
                        tempFolder.Name = "TempAntiRagdoll"
                        tempFolder.Parent = player
                    end
                    constraint.Parent = tempFolder
                end
            end
        end

        -- 4. Detener animaciones de inmovilización (guardando para restaurar)
        if hum.Animator then
            local animator = hum.Animator
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local animId = track.Animation.AnimationId:lower()
                local killList = {"ragdoll", "knock", "stun", "fall", "down", "hit"}
                for _, keyword in ipairs(killList) do
                    if animId:find(keyword) then
                        -- Guardar la pista antes de detenerla
                        local alreadySaved = false
                        for _, saved in ipairs(modifiedObjects.animations) do
                            if saved == track then alreadySaved = true break end
                        end
                        if not alreadySaved then
                            table.insert(modifiedObjects.animations, track)
                        end
                        track:Stop()
                        break
                    end
                end
            end
        end

        -- 5. Desactivar scripts sospechosos (sin destruir)
        for _, scriptObj in ipairs(char:GetDescendants()) do
            if scriptObj:IsA("Script") then
                local nameLower = scriptObj.Name:lower()
                if nameLower:find("ragdoll") or nameLower:find("stun") or nameLower:find("knockout") then
                    local alreadySaved = false
                    for _, saved in ipairs(modifiedObjects.scripts) do
                        if saved == scriptObj then alreadySaved = true break end
                    end
                    if not alreadySaved then
                        table.insert(modifiedObjects.scripts, scriptObj)
                    end
                    scriptObj.Disabled = true
                end
            elseif scriptObj:IsA("LocalScript") then
                local nameLower = scriptObj.Name:lower()
                if nameLower:find("ragdoll") or nameLower:find("stun") or nameLower:find("knockout") then
                    local alreadySaved = false
                    for _, saved in ipairs(modifiedObjects.scripts) do
                        if saved == scriptObj then alreadySaved = true break end
                    end
                    if not alreadySaved then
                        table.insert(modifiedObjects.scripts, scriptObj)
                    end
                    local tempFolder = player:FindFirstChild("TempAntiRagdoll") 
                    if not tempFolder then
                        tempFolder = Instance.new("Folder")
                        tempFolder.Name = "TempAntiRagdoll"
                        tempFolder.Parent = player
                    end
                    scriptObj.Parent = tempFolder
                end
            end
        end

        -- 6. Mover partes con nombres sospechosos
        local blacklistNames = {"ragdoll", "stun", "knock", "fall", "down", "hit", "grab", "freeze", "paralyze", "body"}
        for _, obj in ipairs(char:GetDescendants()) do
            if obj:IsA("BasePart") then
                local nameLower = obj.Name:lower()
                for _, word in ipairs(blacklistNames) do
                    if nameLower:find(word) then
                        -- Guardar estado original
                        local alreadySaved = false
                        for _, saved in ipairs(modifiedObjects.parts) do
                            if saved.part == obj then alreadySaved = true break end
                        end
                        if not alreadySaved then
                            table.insert(modifiedObjects.parts, {
                                part = obj,
                                anchored = obj.Anchored
                            })
                        end
                        -- Mover a folder temporal
                        local tempFolder = player:FindFirstChild("TempAntiRagdoll") 
                        if not tempFolder then
                            tempFolder = Instance.new("Folder")
                            tempFolder.Name = "TempAntiRagdoll"
                            tempFolder.Parent = player
                        end
                        obj.Parent = tempFolder
                        break
                    end
                end
            end
        end
    end)
end

-- Iniciar/Detener el loop de protección
local function enableAntiRagdoll()
    if AntiRagdollEnabled then return end
    AntiRagdollEnabled = true
    if antiRagdollHeartbeat then antiRagdollHeartbeat:Disconnect() end
    antiRagdollHeartbeat = RunService.Heartbeat:Connect(applyAntiRagdollProtections)
    print("🛡️ Anti-Ragdoll ACTIVADO")
end

local function disableAntiRagdoll()
    if not AntiRagdollEnabled then return end
    AntiRagdollEnabled = false
    if antiRagdollHeartbeat then
        antiRagdollHeartbeat:Disconnect()
        antiRagdollHeartbeat = nil
    end
    restoreAll()
    print("⚠️ Anti-Ragdoll DESACTIVADO - personaje restaurado")
end

-- Manejo de respawn
local function onCharacterAdded(newChar)
    -- Limpiar almacén al cambiar de personaje
    modifiedObjects.constraints = {}
    modifiedObjects.animations = {}
    modifiedObjects.scripts = {}
    modifiedObjects.parts = {}
    
    -- Si CARNAGE está activado, reactivar anti-ragdoll
    if CarnageEnabled then
        enableAntiRagdoll()
    else
        disableAntiRagdoll()
    end
end

antiRagdollCharConnection = player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end

-- ==================== FUNCIÓN HEADSIT SENTADO REAL ====================
local function applyHeadsit(target)
    if not target or not target.Character then return end
    
    local localChar = player.Character
    local targetChar = target.Character
    
    if not localChar or not targetChar then return end
    
    -- Obtener partes necesarias
    local targetHead = targetChar:FindFirstChild("Head")
    local targetHumanoid = targetChar:FindFirstChild("Humanoid")
    local localHumanoid = localChar:FindFirstChild("Humanoid")
    local localHRP = localChar:FindFirstChild("HumanoidRootPart")
    
    if not targetHead or not targetHumanoid or not localHumanoid or not localHRP then return end
    
    -- Verificar que el objetivo esté vivo
    if targetHumanoid.Health <= 0 then return end
    
    -- 1. Reproducir animación de sentado (si existe)
    local animator = localHumanoid:FindFirstChildOfClass("Animator")
    if animator then
        -- Detener animaciones actuales
        for _, track in pairs(animator:GetPlayingAnimationTracks()) do
            track:Stop()
        end
        -- Cargar y reproducir animación de sentado (ID común de silla)
        local sitAnim = Instance.new("Animation")
        sitAnim.AnimationId = "rbxassetid://507766019" -- Animación de sentado genérica
        local sitTrack = animator:LoadAnimation(sitAnim)
        sitTrack:Play()
    end
    
    -- 2. Configurar para que parezca sentado
    localHumanoid.PlatformStand = true   -- Evita caídas y desactiva físicas
    
    -- Posición: justo encima de la cabeza con offset bajo (0.3) para simular sentado
    local sitPosition = targetHead.Position + Vector3.new(0, 0.3, 0)
    -- Rotación: mirando hacia la misma dirección que la cabeza del objetivo
    local lookVector = targetHead.CFrame.LookVector
    local sitCFrame = CFrame.new(sitPosition, sitPosition + lookVector)
    
    -- Mover al jugador local a la posición SENTADA
    pcall(function()
        localHRP.CFrame = sitCFrame
        localHRP.Velocity = Vector3.new(0,0,0)
        localHRP.RotVelocity = Vector3.new(0,0,0)
    end)
    
    -- Actualizar objetivo actual
    currentHeadsitTarget = target
end

local function stopHeadsit()
    if headsitConnection then
        headsitConnection:Disconnect()
        headsitConnection = nil
    end
    
    -- Restaurar estado normal del jugador
    local localChar = player.Character
    if localChar then
        local localHumanoid = localChar:FindFirstChild("Humanoid")
        if localHumanoid then
            localHumanoid.PlatformStand = false
            
            -- Detener todas las animaciones
            local animator = localHumanoid:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in pairs(animator:GetPlayingAnimationTracks()) do
                    track:Stop()
                end
            end
        end
    end
    
    currentHeadsitTarget = nil
    headsitActive = false
end

local function startHeadsit(initialTarget)
    if headsitActive then
        stopHeadsit()
    end
    
    if not initialTarget then return end
    
    headsitActive = true
    applyHeadsit(initialTarget)
    
    -- Bucle principal de mantenimiento y cambio automático de objetivo
    headsitConnection = RunService.Heartbeat:Connect(function()
        if not CarnageEnabled then
            stopHeadsit()
            return
        end
        
        local localChar = player.Character
        if not localChar then
            stopHeadsit()
            return
        end
        
        local localHRP = localChar:FindFirstChild("HumanoidRootPart")
        if not localHRP then return end
        
        -- Verificar si el objetivo actual sigue siendo válido
        local target = currentHeadsitTarget
        local targetValid = false
        
        if target and target.Character then
            local targetChar = target.Character
            local targetHead = targetChar:FindFirstChild("Head")
            local targetHumanoid = targetChar:FindFirstChild("Humanoid")
            if targetHead and targetHumanoid and targetHumanoid.Health > 0 then
                targetValid = true
                -- Mantener la posición en la cabeza
                local sitPosition = targetHead.Position + Vector3.new(0, 0.3, 0)
                local lookVector = targetHead.CFrame.LookVector
                local sitCFrame = CFrame.new(sitPosition, sitPosition + lookVector)
                pcall(function()
                    localHRP.CFrame = sitCFrame
                    localHRP.Velocity = Vector3.new(0,0,0)
                    localHRP.RotVelocity = Vector3.new(0,0,0)
                end)
            end
        end
        
        -- Si el objetivo actual no es válido, buscar uno nuevo
        if not targetValid then
            local newTarget = targetPlayer  -- Si hay objetivo específico, usarlo
            if not newTarget then
                -- Buscar el jugador más cercano dentro del rango
                local myPos = localHRP.Position
                local closestDist = AURA_RANGE
                local closest = nil
                
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= player and not isPlayerProhibited(p) and p.Character and p.Character:FindFirstChild("Humanoid") then
                        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local dist = (hrp.Position - myPos).Magnitude
                            if dist <= closestDist then
                                closestDist = dist
                                closest = p
                            end
                        end
                    end
                end
                newTarget = closest
            end
            
            if newTarget then
                applyHeadsit(newTarget)  -- Cambia al nuevo objetivo y reproduce animación
            end
        end
    end)
end

-- ==================== NUEVO SISTEMA DE INVISIBILIDAD FALSA ====================
do
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")

    local LocalPlayer = Players.LocalPlayer
    local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local Humanoid = Character:WaitForChild("Humanoid")
    local RootPart = Humanoid.RootPart

    local DepthStuds = 20
    local VerticalOffset = Vector3.new(0, -DepthStuds, 0)
    local RotationUpsideDown = CFrame.Angles(0, 0, math.rad(180))
    local OldPosition = RootPart.CFrame

    local IsEnabled = false
    local IsSequencing = false
    local Connections = {}
    local RenderSteps = {}

    local function GenerateUniqueName()
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        local name = ""
        for i = 1, 20 do
            local rand = math.random(1, #chars)
            name = name .. chars:sub(rand, rand)
        end
        return name
    end

    local function Cleanup()
        for _, conn in ipairs(Connections) do
            conn:Disconnect()
        end
        Connections = {}
        for _, step in ipairs(RenderSteps) do
            RunService:UnbindFromRenderStep(step)
        end
        RenderSteps = {}
    end

    -- Highlight permanente (amarillo)
    local HighlightInstance = Instance.new("Highlight")
    HighlightInstance.Adornee = Character
    HighlightInstance.Enabled = true
    HighlightInstance.FillColor = Color3.fromRGB(255, 255, 0)
    HighlightInstance.OutlineColor = Color3.fromRGB(255, 200, 0)
    HighlightInstance.FillTransparency = 0.5
    HighlightInstance.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    HighlightInstance.Parent = game:GetService("CoreGui")

    -- Activar invisibilidad
    local function ActivateFakeInvisibility()
        if IsEnabled then return end
        Cleanup()
        IsEnabled = true
        OldPosition = RootPart.CFrame

        local step1 = GenerateUniqueName()
        local step2 = GenerateUniqueName()

        RunService:BindToRenderStep(step1, Enum.RenderPriority.Camera.Value - 5, function()
            if not RootPart then return end
            RootPart.CFrame = OldPosition
        end)
        table.insert(RenderSteps, step1)

        RunService:BindToRenderStep(step2, Enum.RenderPriority.Camera.Value + 5, function()
            if not RootPart then return end
            RootPart.CFrame = CFrame.new(RootPart.Position + VerticalOffset) * RotationUpsideDown
        end)
        table.insert(RenderSteps, step2)

        table.insert(Connections, RunService.PreAnimation:Connect(function()
            if not RootPart then return end
            RootPart.CFrame = OldPosition
        end))

        table.insert(Connections, RunService.PostSimulation:Connect(function()
            if not RootPart then return end
            OldPosition = RootPart.CFrame
            RootPart.CFrame = CFrame.new(RootPart.Position + VerticalOffset) * RotationUpsideDown
        end))
    end

    -- Desactivar invisibilidad
    local function DeactivateFakeInvisibility()
        if not IsEnabled then return end
        Cleanup()
        if RootPart then
            RootPart.CFrame = OldPosition
        end
        IsEnabled = false
    end

    -- Bucle de secuencia con patrón: 0.8s ON, 0.1s OFF
    local function SequenceLoop()
        while IsSequencing do
            ActivateFakeInvisibility()
            task.wait(0.3)
            
            DeactivateFakeInvisibility()
            task.wait(0.1)
        end
    end

    -- Iniciar secuencia
    local function StartSequence()
        if IsSequencing then return end
        IsSequencing = true
        if IsEnabled then
            DeactivateFakeInvisibility()
        end
        task.spawn(SequenceLoop)
    end

    -- Detener secuencia
    local function StopSequence()
        if not IsSequencing then return end
        IsSequencing = false
        if IsEnabled then
            DeactivateFakeInvisibility()
        end
    end

    -- Alternar secuencia
    local function ToggleSequence()
        if IsSequencing then
            StopSequence()
        else
            StartSequence()
        end
    end

    -- Reasignar al cambiar personaje
    LocalPlayer.CharacterAdded:Connect(function(newChar)
        Character = newChar
        Humanoid = newChar:WaitForChild("Humanoid")
        RootPart = Humanoid.RootPart
        OldPosition = RootPart.CFrame

        if HighlightInstance then
            HighlightInstance.Adornee = Character
        end

        if IsSequencing then
            task.wait(0.03)
            if IsEnabled then
                DeactivateFakeInvisibility()
            end
            IsSequencing = false
            StartSequence()
        end
    end)

    -- Exportar funciones
    _G.ToggleFakeInvisSequence = ToggleSequence
    _G.IsFakeInvisSequencing = function() return IsSequencing end
    _G.StopFakeInvisSequence = StopSequence
    _G.StartFakeInvisSequence = StartSequence
end

-- ==================== FUNCIÓN DE DETECCIÓN DE ZONA ====================
local function estaEnZona(jugador)
    if not jugador or not jugador.Character then return false end
    
    local character = jugador.Character
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
    
    if not rootPart then return false end
    
    local pos = rootPart.Position
    
    -- Verificar si está dentro de los límites
    return pos.X >= limiteMin.X and pos.X <= limiteMax.X
       and pos.Y >= limiteMin.Y and pos.Y <= limiteMax.Y
       and pos.Z >= limiteMin.Z and pos.Z <= limiteMax.Z
end

-- ==================== FUNCIÓN PARA DETECTAR COMPORTAMIENTO ANÓMALO DEL TARGET ====================
local function detectarComportamientoAnomalo()
    if not targetPlayer or not targetPlayer.Character then return false end
    
    local targetChar = targetPlayer.Character
    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
    
    if not targetHRP then return false end
    
    local currentTime = tick()
    local currentPos = targetHRP.Position
    
    -- CASO 1: Teleport repentino (detección de fake invis que manda lejos)
    if ultimaPosicionTarget then
        local distanciaRecorrida = (currentPos - ultimaPosicionTarget).Magnitude
        
        -- Si la distancia recorrida es extremadamente grande (> 100 studs), es un teleport
        if distanciaRecorrida > 100 then
            teleportCount = teleportCount + 1
            lastTeleportTime = currentTime
            print("🚨 TELEPORT DETECTADO! Distancia: " .. math.floor(distanciaRecorrida))
            return true
        end
        
        -- CASO 2: Velocidad anómala (si se mueve más rápido de lo normal)
        if ultimaDistancia then
            local velocidad = distanciaRecorrida / zoneCheckInterval
            if velocidad > 200 then -- Más de 200 studs/segundo = sospechoso
                print("🚨 VELOCIDAD ANÓMALA DETECTADA: " .. math.floor(velocidad) .. " studs/s")
                return true
            end
        end
        
        ultimaDistancia = distanciaRecorrida
    end
    
    -- CASO 3: Múltiples teleports en poco tiempo
    if teleportCount >= 3 and (currentTime - lastTeleportTime) < 2 then
        print("🚨 MÚLTIPLES TELEPORTS DETECTADOS")
        return true
    end
    
    ultimaPosicionTarget = currentPos
    return false
end

-- ==================== FUNCIÓN PARA MANTENER ESTABILIDAD INSTANTÁNEA EN EL RING ====================
local function mantenerEstabilidadInstantanea()
    local localChar = player.Character
    if not localChar then return end
    
    local localHRP = localChar:FindFirstChild("HumanoidRootPart")
    local localHumanoid = localChar:FindFirstChild("Humanoid")
    
    if not localHRP or not localHumanoid then return end
    
    -- Verificar si estamos dentro del ring
    local pos = localHRP.Position
    local dentroDelRing = pos.X >= limiteMin.X and pos.X <= limiteMax.X
                      and pos.Y >= limiteMin.Y and pos.Y <= limiteMax.Y
                      and pos.Z >= limiteMin.Z and pos.Z <= limiteMax.Z
    
    -- DETECCIÓN DE COMPORTAMIENTO ANÓMALO DEL TARGET
    local comportamientoAnomalo = false
    if targetPlayer and CarnageEnabled then
        comportamientoAnomalo = detectarComportamientoAnomalo()
    end
    
    -- SI DETECTAMOS ALGO ANÓMALO O ESTAMOS FUERA DEL RING → REPOSICIONAMIENTO INSTANTÁNEO
    if comportamientoAnomalo or not dentroDelRing then
        -- Reposicionar INSTANTÁNEAMENTE en el centro BAJO del ring
        pcall(function()
            localHRP.CFrame = CFrame.new(posicionRingBaja)
            localHRP.Velocity = Vector3.new(0,0,0)
            localHRP.RotVelocity = Vector3.new(0,0,0)
            
            if comportamientoAnomalo then
                print("⚡ REPOSICIONAMIENTO INSTANTÁNEO POR COMPORTAMIENTO ANÓMALO")
            else
                print("⚡ REPOSICIONAMIENTO INSTANTÁNEO POR SALIDA DEL RING")
            end
        end)
        
        -- Resetear contadores de teleport
        teleportCount = 0
    end
    
    -- Mantener animación estable si no estamos en headsit
    if not headsitActive then
        -- Asegurar que no estamos en estados raros
        if localHumanoid:GetState() == Enum.HumanoidStateType.Physics or
           localHumanoid:GetState() == Enum.HumanoidStateType.FallingDown then
            localHumanoid:ChangeState(Enum.HumanoidStateType.Running)
        end
    end
end

-- ==================== FUNCIONES PARA CREAR EL CUBO ====================
local function crearRangoVisual()
    -- Destruir rango anterior si existe
    if rangoVisual and rangoVisual.Parent then
        rangoVisual:Destroy()
    end
    
    print("⚡ CREANDO CUBO DEL RING")
    
    -- ===== CUBO PRINCIPAL (totalmente invisible) =====
    local cubo = Instance.new("Part")
    cubo.Name = "CUBO_INVISIBLE_" .. player.Name
    cubo.Size = ZONE_CONFIG.TAMANO
    cubo.Position = ZONE_CONFIG.POSICION
    cubo.Anchored = true
    cubo.CanCollide = false
    cubo.Transparency = ZONE_CONFIG.TRANSPARENCIA
    cubo.BrickColor = BrickColor.new(ZONE_CONFIG.COLOR)
    cubo.Material = Enum.Material.SmoothPlastic
    cubo.Shape = Enum.PartType.Block
    cubo.CastShadow = true
    
    -- ===== CONTORNO ROJO VISIBLE =====
    local function crearBorde(tamano, posicion)
        local borde = Instance.new("Part")
        borde.Size = tamano
        borde.Position = posicion
        borde.Anchored = true
        borde.CanCollide = false
        borde.Transparency = 0.7
        borde.BrickColor = BrickColor.new(ZONE_CONFIG.COLOR)
        borde.Material = Enum.Material.Neon
        borde.Parent = cubo
        return borde
    end
    
    local s = ZONE_CONFIG.TAMANO
    local p = ZONE_CONFIG.POSICION
    
    -- Bordes horizontales superiores
    crearBorde(Vector3.new(s.X, 0.2, 0.2), p + Vector3.new(0, s.Y/2, s.Z/2))
    crearBorde(Vector3.new(s.X, 0.2, 0.2), p + Vector3.new(0, s.Y/2, -s.Z/2))
    crearBorde(Vector3.new(0.2, 0.2, s.Z), p + Vector3.new(s.X/2, s.Y/2, 0))
    crearBorde(Vector3.new(0.2, 0.2, s.Z), p + Vector3.new(-s.X/2, s.Y/2, 0))
    
    -- Bordes horizontales inferiores
    crearBorde(Vector3.new(s.X, 0.2, 0.2), p + Vector3.new(0, -s.Y/2, s.Z/2))
    crearBorde(Vector3.new(s.X, 0.2, 0.2), p + Vector3.new(0, -s.Y/2, -s.Z/2))
    crearBorde(Vector3.new(0.2, 0.2, s.Z), p + Vector3.new(s.X/2, -s.Y/2, 0))
    crearBorde(Vector3.new(0.2, 0.2, s.Z), p + Vector3.new(-s.X/2, -s.Y/2, 0))
    
    -- Bordes verticales
    crearBorde(Vector3.new(0.2, s.Y, 0.2), p + Vector3.new(s.X/2, 0, s.Z/2))
    crearBorde(Vector3.new(0.2, s.Y, 0.2), p + Vector3.new(s.X/2, 0, -s.Z/2))
    crearBorde(Vector3.new(0.2, s.Y, 0.2), p + Vector3.new(-s.X/2, 0, s.Z/2))
    crearBorde(Vector3.new(0.2, s.Y, 0.2), p + Vector3.new(-s.X/2, 0, -s.Z/2))
    
    -- Poner en el workspace
    cubo.Parent = Workspace
    print("✅ CUBO DEL RING CREADO")
    
    rangoVisual = cubo
    return cubo
end

-- ==================== FUNCIONES AUXILIARES ====================
local function isPlayerProhibited(playerObj)
    if not playerObj then return false end
    local playerNameLower = playerObj.Name:lower()
    for _, prohibitedName in ipairs(PROHIBITED_USERS) do
        if playerNameLower == prohibitedName:lower() then
            return true
        end
    end
    local displayNameLower = playerObj.DisplayName:lower()
    for _, prohibitedName in ipairs(PROHIBITED_USERS) do
        if displayNameLower == prohibitedName:lower() then
            return true
        end
    end
    return false
end

local function findPlayerByPartialName(inputText)
    if inputText == "" or inputText:lower() == "todos" or inputText:lower() == "all" then
        return nil, "TODOS"
    end
    local searchText = inputText:lower():gsub("%s+", "")
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= player and not isPlayerProhibited(p) then
            if p.Name:lower() == searchText then
                return p, p.Name
            end
            if p.DisplayName:lower() == searchText then
                return p, p.DisplayName
            end
        end
    end
    if #searchText >= 3 then
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= player and not isPlayerProhibited(p) then
                if p.Name:lower():sub(1, #searchText) == searchText then
                    return p, p.Name
                end
            end
        end
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= player and not isPlayerProhibited(p) then
                if p.DisplayName:lower():sub(1, #searchText) == searchText then
                    return p, p.DisplayName
                end
            end
        end
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= player and not isPlayerProhibited(p) then
                if p.Name:lower():find(searchText, 1, true) then
                    return p, p.Name
                end
            end
        end
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= player and not isPlayerProhibited(p) then
                if p.DisplayName:lower():find(searchText, 1, true) then
                    return p, p.DisplayName
                end
            end
        end
    end
    if #searchText > 0 and #searchText < 3 then
        return false, "Mínimo 3 letras para buscar"
    end
    return false, "Jugador no encontrado o está en lista prohibida"
end

-- ==================== SISTEMA ESP OPTIMIZADO ====================
local function createESP(playerObj)
    if not playerObj or playerObj == player then return end
    if isPlayerProhibited(playerObj) then return end
    if not ESPEnabled then return end

    if not Holder or not Holder.Parent then
        Holder = Instance.new("Folder", game:GetService("CoreGui"))
        Holder.Name = "ESP_" .. tostring(tick())
    end

    local vHolder = Holder:FindFirstChild(playerObj.Name)
    if vHolder then
        vHolder:ClearAllChildren()
        vHolder:Destroy()
    end

    vHolder = Instance.new("Folder")
    vHolder.Name = playerObj.Name
    vHolder.Parent = Holder

    playerConnections[playerObj] = {}

    local function applyESPToCharacter(character)
        if not character or not ESPEnabled then return end
        task.spawn(function()
            local hrp = character:WaitForChild("HumanoidRootPart", 2)
            if not hrp then return end

            local box = Instance.new("BoxHandleAdornment")
            box.Name = "Box"
            box.Size = Vector3.new(4, 7, 4)
            box.Transparency = 0.7
            box.ZIndex = 0
            box.AlwaysOnTop = true
            box.Visible = true
            box.Adornee = hrp
            box.Parent = vHolder

            local nameTag = Instance.new("BillboardGui")
            nameTag.Name = "NameTag"
            nameTag.Enabled = true
            nameTag.Size = UDim2.new(0, 200, 0, 50)
            nameTag.AlwaysOnTop = true
            nameTag.StudsOffset = Vector3.new(0, 5, 0)
            nameTag.MaxDistance = 1000
            nameTag.Adornee = hrp
            nameTag.Parent = vHolder

            local tag = Instance.new("TextLabel", nameTag)
            tag.Name = "Tag"
            tag.BackgroundTransparency = 1
            tag.Position = UDim2.new(0, -50, 0, 0)
            tag.Size = UDim2.new(0, 300, 0, 20)
            tag.TextSize = 22
            tag.TextStrokeColor3 = Color3.new(0, 0, 0)
            tag.TextStrokeTransparency = 0.4
            tag.Text = playerObj.Name
            tag.Font = Enum.Font.SourceSansBold
            tag.TextScaled = false

            local highlight = Instance.new("Highlight")
            highlight.Name = "Highlight"
            highlight.Adornee = character
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillTransparency = 0.5
            highlight.OutlineTransparency = 0
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.Parent = vHolder

            if _G.UseTeamColor then
                box.Color3 = playerObj.TeamColor.Color
                tag.TextColor3 = playerObj.TeamColor.Color
                highlight.FillColor = playerObj.TeamColor.Color
            else
                local color = (player.TeamColor == playerObj.TeamColor) and _G.FriendColor or _G.EnemyColor
                box.Color3 = color
                tag.TextColor3 = color
                highlight.FillColor = color
            end
        end)
    end

    if playerObj.Character then
        applyESPToCharacter(playerObj.Character)
    end

    local charConnection = playerObj.CharacterAdded:Connect(function(character)
        task.wait(0.5)
        if ESPEnabled and vHolder.Parent then
            applyESPToCharacter(character)
        end
    end)

    playerConnections[playerObj].charConnection = charConnection
    playerConnections[playerObj].vHolder = vHolder
end

local function removeESP(playerObj)
    if playerConnections[playerObj] then
        if playerConnections[playerObj].charConnection then
            playerConnections[playerObj].charConnection:Disconnect()
        end
        playerConnections[playerObj] = nil
    end
    if Holder and Holder.Parent then
        local vHolder = Holder:FindFirstChild(playerObj.Name)
        if vHolder then
            vHolder:ClearAllChildren()
            vHolder:Destroy()
        end
    end
end

local function toggleESP()
    ESPEnabled = not ESPEnabled
    if ESPEnabled then
        print("Activando ESP...")
        if Holder and Holder.Parent then
            Holder:Destroy()
        end
        Holder = Instance.new("Folder", game:GetService("CoreGui"))
        Holder.Name = "ESP_" .. tostring(tick())
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= player and not isPlayerProhibited(p) then
                createESP(p)
            end
        end
        espConnection = Players.PlayerAdded:Connect(function(newPlayer)
            if not isPlayerProhibited(newPlayer) then
                createESP(newPlayer)
            end
        end)
        return "ESP Activado"
    else
        print("Desactivando ESP...")
        if espConnection then
            espConnection:Disconnect()
            espConnection = nil
        end
        for _, connections in pairs(playerConnections) do
            if connections.charConnection then
                connections.charConnection:Disconnect()
            end
        end
        playerConnections = {}
        if Holder then
            Holder:ClearAllChildren()
            Holder:Destroy()
            Holder = nil
        end
        return "ESP Desactivado"
    end
end

-- ==================== Main Frame Creator ====================
local function CreateMainFrame(titleText, sizeX, sizeY)
    sizeX = sizeX or 320
    sizeY = sizeY or 380

    local ScreenGui = player.PlayerGui:FindFirstChild("MainFrames") or Instance.new("ScreenGui")
    ScreenGui.Name = "MainFrames"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = player.PlayerGui

    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, sizeX, 0, sizeY)
    Frame.Position = UDim2.new(0.5, -sizeX/2, 0.5, -sizeY/2)
    Frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    Frame.BorderSizePixel = 0
    Frame.ClipsDescendants = true
    Frame.Parent = ScreenGui

    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 12)
    UICorner.Parent = Frame

    local UIGradient = Instance.new("UIGradient")
    UIGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30,30,30)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10,10,10))
    }
    UIGradient.Rotation = 90
    UIGradient.Parent = Frame

    local UIStroke = Instance.new("UIStroke")
    UIStroke.Color = Color3.fromRGB(255,255,255)
    UIStroke.Transparency = 0.4
    UIStroke.Thickness = 1.5
    UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    UIStroke.Parent = Frame

    local DragFrame = Instance.new("Frame")
    DragFrame.Name = "DragFrame"
    DragFrame.Size = UDim2.new(1, 0, 1, 0)
    DragFrame.BackgroundTransparency = 1
    DragFrame.Active = true
    DragFrame.Selectable = false
    DragFrame.Parent = Frame

    local TitleBar = Instance.new("Frame")
    TitleBar.Size = UDim2.new(1, 0, 0, 40)
    TitleBar.BackgroundTransparency = 1
    TitleBar.Parent = Frame

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(0.7, 0, 1, 0)
    Title.Position = UDim2.new(0, 12, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = titleText or "Diogo Br to Bots"
    Title.TextColor3 = Color3.fromRGB(255,255,255)
    Title.TextSize = 20
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TitleBar

    local MinimizeButton = Instance.new("TextButton")
    MinimizeButton.Size = UDim2.new(0, 34, 0, 34)
    MinimizeButton.Position = UDim2.new(1, -80, 0, 3)
    MinimizeButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    MinimizeButton.Text = "-"
    MinimizeButton.TextColor3 = Color3.fromRGB(200, 200, 200)
    MinimizeButton.Font = Enum.Font.GothamBold
    MinimizeButton.TextSize = 24
    MinimizeButton.Parent = TitleBar

    local MinCorner = Instance.new("UICorner")
    MinCorner.CornerRadius = UDim.new(0, 8)
    MinCorner.Parent = MinimizeButton

    local DeleteButton = Instance.new("TextButton")
    DeleteButton.Size = UDim2.new(0, 34, 0, 34)
    DeleteButton.Position = UDim2.new(1, -42, 0, 3)
    DeleteButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    DeleteButton.Text = "X"
    DeleteButton.TextColor3 = Color3.fromRGB(255, 220, 220)
    DeleteButton.Font = Enum.Font.GothamBold
    DeleteButton.TextSize = 22
    DeleteButton.Parent = TitleBar

    local DelCorner = Instance.new("UICorner")
    DelCorner.CornerRadius = UDim.new(0, 8)
    DelCorner.Parent = DeleteButton

    local Content = Instance.new("Frame")
    Content.Name = "Content"
    Content.Size = UDim2.new(1, 0, 1, -40)
    Content.Position = UDim2.new(0, 0, 0, 40)
    Content.BackgroundTransparency = 1
    Content.Parent = Frame

    local minimized = false
    local originalSizeY = sizeY

    MinimizeButton.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            Frame.Size = UDim2.new(0, sizeX, 0, 40)
            MinimizeButton.Text = "+"
            MinimizeButton.TextColor3 = Color3.fromRGB(100, 255, 100)
            Content.Visible = false
        else
            Frame.Size = UDim2.new(0, sizeX, 0, originalSizeY)
            MinimizeButton.Text = "-"
            MinimizeButton.TextColor3 = Color3.fromRGB(200, 200, 200)
            Content.Visible = true
        end
    end)

    DeleteButton.MouseButton1Click:Connect(function()
        if collectConnection then collectConnection:Disconnect() collectConnection = nil end
        if espConnection then espConnection:Disconnect() espConnection = nil end
        ESPEnabled = false
        for _, connections in pairs(playerConnections) do
            if connections.charConnection then connections.charConnection:Disconnect() end
        end
        playerConnections = {}
        if Holder then Holder:Destroy() Holder = nil end
        Frame:Destroy()
    end)

    -- Sistema de arrastre
    local dragging = false
    local dragStart = nil
    local startPos = nil

    local function startDrag(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Frame.Position
            local connection
            connection = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if connection then connection:Disconnect() end
                end
            end)
        end
    end

    local function updateDrag(input)
        if dragging and dragStart then
            local delta = input.Position - dragStart
            Frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end

    Frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local target = input.UserInputState == Enum.InputState.Begin and UserInputService:GetMouseTarget()
            if target then
                local isInteractive = false
                local current = target
                while current and current ~= Frame do
                    if current:IsA("TextButton") or current:IsA("TextBox") then
                        isInteractive = true
                        break
                    end
                    current = current.Parent
                end
                if not isInteractive then startDrag(input) end
            else
                startDrag(input)
            end
        end
    end)

    Frame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateDrag(input)
        end
    end)

    DragFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            startDrag(input)
        end
    end)

    DragFrame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateDrag(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            dragStart = nil
        end
    end)

    return Content
end

--// Crear GUI principal
local content = CreateMainFrame("Diogo Br To Bots", 320, 380)

--// Botón ESP
local espBtn = Instance.new("TextButton")
espBtn.Size = UDim2.new(0.4, 0, 0, 40)
espBtn.Position = UDim2.new(0.075, 0, 0.05, 0)
espBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
espBtn.Text = "ESP: OFF"
espBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
espBtn.Font = Enum.Font.GothamBold
espBtn.TextSize = 16
espBtn.Parent = content

local espCorner = Instance.new("UICorner")
espCorner.CornerRadius = UDim.new(0, 10)
espCorner.Parent = espBtn

local espStroke = Instance.new("UIStroke")
espStroke.Color = Color3.fromRGB(60, 60, 60)
espStroke.Thickness = 1.5
espStroke.Parent = espBtn

--// Botón CARNAGE (Kill Aura + Headsit SENTADO + Anti-Ragdoll)
local carnageBtn = Instance.new("TextButton")
carnageBtn.Size = UDim2.new(0.4, 0, 0, 40)
carnageBtn.Position = UDim2.new(0.525, 0, 0.05, 0)
carnageBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
carnageBtn.Text = "CARNAGE: OFF"
carnageBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
carnageBtn.Font = Enum.Font.GothamBold
carnageBtn.TextSize = 16
carnageBtn.Parent = content

local carnageCorner = Instance.new("UICorner")
carnageCorner.CornerRadius = UDim.new(0, 10)
carnageCorner.Parent = carnageBtn

local carnageStroke = Instance.new("UIStroke")
carnageStroke.Color = Color3.fromRGB(60, 60, 60)
carnageStroke.Thickness = 1.5
carnageStroke.Parent = carnageBtn

--// Función para toggle ESP
local function toggleESPButton()
    local result = toggleESP()
    if ESPEnabled then
        espBtn.Text = "ESP: ON"
        espBtn.TextColor3 = Color3.fromRGB(80, 255, 80)
        espBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 40)
        espStroke.Color = Color3.fromRGB(80, 150, 80)
    else
        espBtn.Text = "ESP: OFF"
        espBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
        espBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        espStroke.Color = Color3.fromRGB(60, 60, 60)
    end
    print("ESP: " .. result)
    return result
end

espBtn.MouseButton1Click:Connect(toggleESPButton)

--// Sistema de selección de objetivo
local targetLabel = Instance.new("TextLabel")
targetLabel.Size = UDim2.new(0.85, 0, 0, 20)
targetLabel.Position = UDim2.new(0.075, 0, 0.20, 0)
targetLabel.BackgroundTransparency = 1
targetLabel.Text = "Objetivo Específico:"
targetLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
targetLabel.Font = Enum.Font.Gotham
targetLabel.TextSize = 14
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.Parent = content

local targetBox = Instance.new("TextBox")
targetBox.Size = UDim2.new(0.85, 0, 0, 35)
targetBox.Position = UDim2.new(0.075, 0, 0.25, 0)
targetBox.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
targetBox.TextColor3 = Color3.fromRGB(255, 255, 255)
targetBox.Font = Enum.Font.Gotham
targetBox.TextSize = 16
targetBox.PlaceholderText = "Escribe 3+ letras y presiona Enter"
targetBox.Text = ""
targetBox.Parent = content

local targetCorner = Instance.new("UICorner")
targetCorner.CornerRadius = UDim.new(0, 8)
targetCorner.Parent = targetBox

local targetStroke = Instance.new("UIStroke")
targetStroke.Color = Color3.fromRGB(60, 60, 60)
targetStroke.Thickness = 1.5
targetStroke.Parent = targetBox

local targetStatus = Instance.new("TextLabel")
targetStatus.Size = UDim2.new(0.85, 0, 0, 20)
targetStatus.Position = UDim2.new(0.075, 0, 0.32, 0)
targetStatus.BackgroundTransparency = 1
targetStatus.Text = "Objetivo actual: TODOS"
targetStatus.TextColor3 = Color3.fromRGB(120, 200, 255)
targetStatus.Font = Enum.Font.Gotham
targetStatus.TextSize = 12
targetStatus.TextXAlignment = Enum.TextXAlignment.Left
targetStatus.Parent = content

local searchResult = Instance.new("TextLabel")
searchResult.Size = UDim2.new(0.85, 0, 0, 25)
searchResult.Position = UDim2.new(0.075, 0, 0.36, 0)
searchResult.BackgroundTransparency = 1
searchResult.Text = "Presiona Enter para buscar"
searchResult.TextColor3 = Color3.fromRGB(150, 150, 150)
searchResult.Font = Enum.Font.Gotham
searchResult.TextSize = 11
searchResult.TextXAlignment = Enum.TextXAlignment.Left
searchResult.TextWrapped = true
searchResult.Parent = content

local function updateTargetStatus()
    if targetPlayer then
        targetStatus.Text = "Objetivo actual: " .. exactTargetName
        targetStatus.TextColor3 = Color3.fromRGB(80, 255, 80)
        searchResult.Text = "✓ Objetivo establecido: " .. exactTargetName
        searchResult.TextColor3 = Color3.fromRGB(80, 255, 80)
        targetBox.Text = exactTargetName
    else
        targetStatus.Text = "Objetivo actual: TODOS"
        targetStatus.TextColor3 = Color3.fromRGB(120, 200, 255)
    end
end

local function searchAndSetTarget()
    local searchText = targetBox.Text:gsub("%s+", "")
    local foundPlayer, resultName = findPlayerByPartialName(searchText)
    if foundPlayer then
        targetPlayer = foundPlayer
        exactTargetName = resultName
        targetPlayerName = exactTargetName
        updateTargetStatus()
        searchResult.Text = "✓ Encontrado: " .. exactTargetName .. " (Usuario: " .. foundPlayer.Name .. ")"
        searchResult.TextColor3 = Color3.fromRGB(80, 255, 80)
    elseif foundPlayer == nil then
        targetPlayer = nil
        exactTargetName = "TODOS"
        targetPlayerName = ""
        updateTargetStatus()
        searchResult.Text = "✓ Modo: TODOS"
        searchResult.TextColor3 = Color3.fromRGB(120, 200, 255)
    else
        searchResult.Text = resultName
        searchResult.TextColor3 = Color3.fromRGB(255, 80, 80)
    end
    task.wait(3)
    if searchResult.Text:sub(1,1) == "✓" or searchResult.Text:find("no encontrado") or searchResult.Text:find("Mínimo") then
        searchResult.Text = "Presiona Enter para buscar"
        searchResult.TextColor3 = Color3.fromRGB(150, 150, 150)
    end
end

targetBox.FocusLost:Connect(function(enterPressed) if enterPressed then searchAndSetTarget() end end)
targetBox:GetPropertyChangedSignal("Text"):Connect(function()
    local currentText = targetBox.Text:gsub("%s+", "")
    if currentText == "" then
        targetPlayer = nil
        exactTargetName = "TODOS"
        targetPlayerName = ""
        updateTargetStatus()
    end
end)

--// Botón para Fake Invisibilidad
local fakeInvisBtn = Instance.new("TextButton")
fakeInvisBtn.Size = UDim2.new(0.4, 0, 0, 30)
fakeInvisBtn.Position = UDim2.new(0.075, 0, 0.55, 0)
fakeInvisBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
fakeInvisBtn.Text = "Fake Invis: OFF (T)"
fakeInvisBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
fakeInvisBtn.Font = Enum.Font.GothamBold
fakeInvisBtn.TextSize = 14
fakeInvisBtn.Parent = content

local fakeInvisCorner = Instance.new("UICorner")
fakeInvisCorner.CornerRadius = UDim.new(0, 6)
fakeInvisCorner.Parent = fakeInvisBtn

local fakeInvisStroke = Instance.new("UIStroke")
fakeInvisStroke.Color = Color3.fromRGB(60, 60, 60)
fakeInvisStroke.Thickness = 1.5
fakeInvisStroke.Parent = fakeInvisBtn

-- Función para actualizar el botón según el estado de la secuencia
local function updateFakeInvisButton()
    if _G.IsFakeInvisSequencing and _G.IsFakeInvisSequencing() then
        fakeInvisBtn.Text = "Fake Invis: ON (T)"
        fakeInvisBtn.TextColor3 = Color3.fromRGB(80, 255, 80)
        fakeInvisBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 40)
        fakeInvisStroke.Color = Color3.fromRGB(80, 150, 80)
    else
        fakeInvisBtn.Text = "Fake Invis: OFF (T)"
        fakeInvisBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
        fakeInvisBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        fakeInvisStroke.Color = Color3.fromRGB(60, 60, 60)
    end
end

fakeInvisBtn.MouseButton1Click:Connect(function()
    if _G.ToggleFakeInvisSequence then
        _G.ToggleFakeInvisSequence()
        updateFakeInvisButton()
    end
end)

-- Info de CARNAGE
local carnageInfo = Instance.new("TextLabel")
carnageInfo.Size = UDim2.new(0.85, 0, 0, 25)
carnageInfo.Position = UDim2.new(0.075, 0, 0.61, 0)
carnageInfo.BackgroundTransparency = 1
carnageInfo.Text = "⚡ CARNAGE: Kill Aura + HEADSIT + ANTI-RAGDOLL"
carnageInfo.TextColor3 = Color3.fromRGB(255, 100, 255)
carnageInfo.Font = Enum.Font.GothamBold
carnageInfo.TextSize = 11
carnageInfo.TextXAlignment = Enum.TextXAlignment.Left
carnageInfo.TextWrapped = true
carnageInfo.Parent = content

-- Info de Zona
local zonaInfo = Instance.new("TextLabel")
zonaInfo.Size = UDim2.new(0.85, 0, 0, 25)
zonaInfo.Position = UDim2.new(0.075, 0, 0.64, 0)
zonaInfo.BackgroundTransparency = 1
zonaInfo.Text = "🎯 ZONA RING: Detección INSTANTÁNEA + Anti-Bug"
zonaInfo.TextColor3 = Color3.fromRGB(100, 200, 255)
zonaInfo.Font = Enum.Font.GothamBold
zonaInfo.TextSize = 11
zonaInfo.TextXAlignment = Enum.TextXAlignment.Left
zonaInfo.TextWrapped = true
zonaInfo.Parent = content

--// Separador visual
local separator = Instance.new("Frame")
separator.Size = UDim2.new(0.85, 0, 0, 1)
separator.Position = UDim2.new(0.075, 0, 0.48, 0)
separator.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
separator.BorderSizePixel = 0
separator.Parent = content

-- Info de teclas
local keysInfo = Instance.new("TextLabel")
keysInfo.Size = UDim2.new(0.85, 0, 0, 25)
keysInfo.Position = UDim2.new(0.075, 0, 0.70, 0)
keysInfo.BackgroundTransparency = 1
keysInfo.Text = "Teclas: Q=ESP | E=CARNAGE | T=Fake Invis"
keysInfo.TextColor3 = Color3.fromRGB(200, 200, 100)
keysInfo.Font = Enum.Font.GothamBold
keysInfo.TextSize = 12
keysInfo.TextXAlignment = Enum.TextXAlignment.Left
keysInfo.Parent = content

--// Función para toggle CARNAGE (Kill Aura + Headsit SENTADO + Anti-Ragdoll)
local function toggleCarnage()
    CarnageEnabled = not CarnageEnabled
    if CarnageEnabled then
        carnageBtn.Text = "CARNAGE: ON"
        carnageBtn.TextColor3 = Color3.fromRGB(80, 255, 80)
        carnageBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 40)
        carnageStroke.Color = Color3.fromRGB(80, 150, 80)
        
        -- Activar Anti-Ragdoll
        enableAntiRagdoll()
        
        -- Resetear contadores de detección
        teleportCount = 0
        ultimaPosicionTarget = nil
        ultimaDistancia = nil
        
        -- Determinar el objetivo inicial para Headsit (SOLO EL TARGET)
        local initialTarget = targetPlayer
        
        if initialTarget and estaEnZona(initialTarget) then
            startHeadsit(initialTarget)
            targetEnZona = true
        else
            -- Si no hay target en zona, activar fake invis
            if _G.StartFakeInvisSequence then
                _G.StartFakeInvisSequence()
                updateFakeInvisButton()
            end
            targetEnZona = false
        end
        
        -- Expandir hitboxes (SOLO DEL TARGET)
        if targetPlayer and targetPlayer.Character and not isPlayerProhibited(targetPlayer) then
            local hrp = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                originalSizes[hrp] = hrp.Size
                hrp.Size = HITBOX_SIZE
            end
        end
        
        -- Conectar Kill Aura (SOLO ATACA AL TARGET)
        if targetPlayer then
            collectConnection = RunService.Heartbeat:Connect(function(deltaTime)
                if not CarnageEnabled then return end
                if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
                if not targetPlayer or not targetPlayer.Character then return end
                
                local currentTime = tick()
                if currentTime - lastAttackTime < attackCooldown then return end
                
                local myHRP = player.Character.HumanoidRootPart
                local hum = targetPlayer.Character:FindFirstChild("Humanoid")
                local hrp = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                
                if hum and hum.Health > 0 and hrp then
                    local dist = (hrp.Position - myHRP.Position).Magnitude
                    if dist <= AURA_RANGE then
                        local args = {
                            hum,
                            vector.create(myHRP.Position.X, myHRP.Position.Y, myHRP.Position.Z)
                        }
                        pcall(function()
                            HitRemote:InvokeServer(unpack(args))
                            lastAttackTime = currentTime
                        end)
                    end
                end
            end)
        end
        
        -- Iniciar monitoreo de zona con DETECCIÓN INSTANTÁNEA
        task.spawn(function()
            while CarnageEnabled do
                task.wait(zoneCheckInterval) -- 0.1 segundos
                
                -- Verificar si el target está en zona
                local targetEnZonaActual = false
                
                if targetPlayer and targetPlayer.Character and not isPlayerProhibited(targetPlayer) then
                    targetEnZonaActual = estaEnZona(targetPlayer)
                end
                
                -- Cambiar estado según detección
                if targetEnZonaActual and not targetEnZona then
                    -- Target entró a zona: activar headsit, desactivar fake invis
                    targetEnZona = true
                    if _G.StopFakeInvisSequence then
                        _G.StopFakeInvisSequence()
                        updateFakeInvisButton()
                    end
                    if not headsitActive and CarnageEnabled then
                        startHeadsit(targetPlayer)
                    end
                    print("🎯 Target detectado en zona - HEADSIT ACTIVADO")
                    
                elseif not targetEnZonaActual and targetEnZona then
                    -- Target salió de zona: desactivar headsit, activar fake invis
                    targetEnZona = false
                    stopHeadsit()
                    if _G.StartFakeInvisSequence and CarnageEnabled then
                        _G.StartFakeInvisSequence()
                        updateFakeInvisButton()
                    end
                    print("👻 Target fuera de zona - FAKE INVIS ACTIVADO")
                end
                
                -- Mantener estabilidad INSTANTÁNEA en el ring (detecta teleports y bugs)
                mantenerEstabilidadInstantanea()
            end
        end)
        
    else
        carnageBtn.Text = "CARNAGE: OFF"
        carnageBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
        carnageBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        carnageStroke.Color = Color3.fromRGB(60, 60, 60)
        
        -- Detener Headsit
        stopHeadsit()
        
        -- Desactivar Anti-Ragdoll (restaura todo)
        disableAntiRagdoll()
        
        -- Desactivar fake invis si está activo
        if _G.StopFakeInvisSequence then
            _G.StopFakeInvisSequence()
            updateFakeInvisButton()
        end
        
        if collectConnection then collectConnection:Disconnect() collectConnection = nil end
        for hrp, oldSize in pairs(originalSizes) do
            if hrp and hrp.Parent then hrp.Size = oldSize end
        end
        originalSizes = {}
        lastAttackTime = 0
        targetEnZona = false
    end
end

carnageBtn.MouseButton1Click:Connect(toggleCarnage)

--// SISTEMA DE TECLAS
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Q then
        toggleESPButton()
    elseif input.KeyCode == Enum.KeyCode.E then
        toggleCarnage()
        print("CARNAGE: " .. (CarnageEnabled and "Activado" or "Desactivado"))
    elseif input.KeyCode == Enum.KeyCode.T then
        if _G.ToggleFakeInvisSequence then
            _G.ToggleFakeInvisSequence()
            updateFakeInvisButton()
        end
    end
end)

-- ============ INICIALIZACIÓN DE ZONA ============
-- Crear el cubo visible del ring
crearRangoVisual()

-- Calcular posición BAJA del ring (centro, parte baja)
posicionRingBaja = ZONE_CONFIG.POSICION - Vector3.new(0, ZONE_CONFIG.TAMANO.Y/2 - 2, 0)

-- Inicializar estados
updateTargetStatus()
updateFakeInvisButton()

-- Loop de estabilidad constante (incluso sin CARNAGE activado)
RunService.Heartbeat:Connect(function()
    if CarnageEnabled then
        -- La estabilidad ya se maneja en el loop de CARNAGE
    else
        -- Si CARNAGE está desactivado, igual mantener estabilidad básica
        mantenerEstabilidadInstantanea()
    end
end)

-- Jugadores entrantes/salientes
Players.PlayerAdded:Connect(function(playerJoined)
    if isPlayerProhibited(playerJoined) then return end
    if not targetPlayer and targetBox.Text == "" then return end
    if targetBox.Text ~= "" then searchAndSetTarget() end
    if ESPEnabled then createESP(playerJoined) end
end)

Players.PlayerRemoving:Connect(function(playerLeft)
    if targetPlayer == playerLeft then
        targetPlayer = nil
        exactTargetName = "TODOS"
        targetPlayerName = ""
        targetBox.Text = ""
        updateTargetStatus()
        searchResult.Text = "⚠️ El objetivo ha salido del juego"
        searchResult.TextColor3 = Color3.fromRGB(255, 150, 50)
    end
    removeESP(playerLeft)
end)

print("=== Diogo Br System - CARNAGE + ANTI-RAGDOLL + ZONA RING (INSTANTÁNEO) ===")
print("✅ CARNAGE = Kill Aura (2000 ataques/s) + HEADSIT SENTADO REAL + ANTI-RAGDOLL")
print("✅ ZONA RING: Solo afecta al TARGET específico")
print("✅ Cuando el TARGET sale de zona → Fake Invis automático")
print("✅ Cuando el TARGET vuelve → Headsit automático")
print("✅ DETECCIÓN INSTANTÁNEA DE TELEPORTS Y COMPORTAMIENTO ANÓMALO")
print("✅ Si el target usa fake invis o se teletransporta → Te reposicionas AL INSTANTE en el ring BAJO")
print("✅ Teclas: Q=ESP | E=CARNAGE | T=Fake Invis")
print("")
print("Sistema ANTI-BUG - ¡REPOSICIONAMIENTO INSTANTÁNEO!")
