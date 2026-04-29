-- ╔══════════════════════════════════════════════════════╗
-- ║  FIO AURA v6.4  ⚡  CYBERPUNK EDITION  — by Fio    ║
-- ║  Aura | Ghost | AntiGrab | Float | Orbit            ║
-- ║  AntiRagdoll | AlwaysRagdoll | Speed                ║
-- ╚══════════════════════════════════════════════════════╝

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local lp = Players.LocalPlayer

-- ═══════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════
local AuraEnabled       = false
local HitboxSize        = 80
local Range             = 35
local currentTarget     = nil
local AutoTargetEnabled = true

local OrbitEnabled = false
local orbitAngle   = 0
local orbitRadius  = 6
local orbitSpeed   = 8

local FloatEnabled = false
local FloatHeight  = 10

local CurrentSpeed       = 25
local SpeedMin, SpeedMax = 5, 200

-- ═══════════════════════════════════════════
--  ATTACK SPEED STATE
-- ═══════════════════════════════════════════
-- Layer architecture (3 layers):
--   L1 → AnimationTrack.AdjustSpeed   : speed up non-looped (attack) anims
--   L2 → __namecall FireServer burst  : extra hits per attack press
--   L3 → hookfunction task.wait       : compress client debounce waits
local AtkSpeedEnabled   = false
local AtkSpeedMult      = 2
local AtkSpdMin, AtkSpdMax = 1, 10
local _atkMT, _atkOldNC = nil, nil
local _atkDetName       = "none"

-- FLIGHT
local FlightEnabled  = false
local FlightSpeed    = 65
local flightAnimIds  = { fly = "97771696507628", idle = "139645860138889" }
local flightAnims    = nil
local flightState    = {
    isFlying = false, isMoving = false,
    currentVelocity = Vector3.new(),
    isTouchingUp = false, isTouchingDown = false,
}

-- ═══════════════════════════════════════════
--  ANTI-RAGDOLL
-- ═══════════════════════════════════════════
local AntiRagdollEnabled = false
local arJoints = {}

local function saveJoints(char)
    arJoints = {}
    for _, j in pairs(char:GetDescendants()) do
        if j:IsA("Motor6D") then
            arJoints[j.Name] = {Part0=j.Part0, Part1=j.Part1, C0=j.C0, C1=j.C1}
        end
    end
end

local function restoreJoints()
    local char = lp.Character; if not char then return end
    for name, d in pairs(arJoints) do
        if d.Part0 and d.Part0.Parent and not d.Part0:FindFirstChild(name) then
            local j = Instance.new("Motor6D")
            j.Name=name; j.Part0=d.Part0; j.Part1=d.Part1
            j.C0=d.C0;   j.C1=d.C1;      j.Parent=d.Part0
        end
    end
end

task.spawn(function()
    saveJoints(lp.Character or lp.CharacterAdded:Wait())
end)

-- ═══════════════════════════════════════════
--  ALWAYS-RAGDOLL
-- ═══════════════════════════════════════════
local AlwaysRagdollEnabled = false
local ragdollData = {}

local AntiAuraEnabled = false
local _antiAuraHB     = nil

local function enableAntiAura()
    if _antiAuraHB then return end
    local t = 0
    _antiAuraHB = RunService.Heartbeat:Connect(function(dt)
        if not AntiAuraEnabled then return end
        local char = lp.Character; if not char then return end
        local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        t = t + dt
        -- Micro-jitter CFrame tiap frame — posisi server selalu bergeser
        -- dari yang client lawan lihat → GetPartBoundsInBox miss
        local jitter = Vector3.new(
            math.sin(t * 97)  * 0.5,
            math.sin(t * 113) * 0.2,
            math.cos(t * 79)  * 0.5
        )
        hrp.CFrame = hrp.CFrame + jitter
    end)
end

local function disableAntiAura()
    if _antiAuraHB then _antiAuraHB:Disconnect(); _antiAuraHB=nil end
end

local function enableAlwaysRagdoll()
    local char = lp.Character; if not char then return end
    local hum  = char:FindFirstChild("Humanoid"); if not hum then return end
    ragdollData = {}
    for _, j in pairs(char:GetDescendants()) do
        if j:IsA("Motor6D") and j.Part0 and j.Part1 then
            j.Enabled = false
            local a0=Instance.new("Attachment"); a0.CFrame=j.C0; a0.Parent=j.Part0
            local a1=Instance.new("Attachment"); a1.CFrame=j.C1; a1.Parent=j.Part1
            local bsc=Instance.new("BallSocketConstraint")
            bsc.Attachment0=a0; bsc.Attachment1=a1
            bsc.LimitsEnabled=true; bsc.UpperAngle=45
            bsc.TwistLimitsEnabled=false; bsc.Parent=j.Part0
            table.insert(ragdollData, {motor=j, bsc=bsc, a0=a0, a1=a1})
        end
    end
    hum:ChangeState(Enum.HumanoidStateType.Physics)
end

local function disableAlwaysRagdoll()
    for _, d in pairs(ragdollData) do
        if d.motor and d.motor.Parent then d.motor.Enabled = true end
        if d.bsc   and d.bsc.Parent   then d.bsc:Destroy()        end
        if d.a0    and d.a0.Parent    then d.a0:Destroy()         end
        if d.a1    and d.a1.Parent    then d.a1:Destroy()         end
    end
    ragdollData = {}
    local h = lp.Character and lp.Character:FindFirstChild("Humanoid")
    if h then h:ChangeState(Enum.HumanoidStateType.Running) end
end



-- ═══════════════════════════════════════════════════════════════
--  FLIGHT MODE
-- ═══════════════════════════════════════════════════════════════
local function loadFlightAnims()
    local char = lp.Character; if not char then return end
    local ok, animator = pcall(function()
        return char:WaitForChild("Humanoid"):WaitForChild("Animator")
    end)
    if not ok then return end
    local res, anims = pcall(function()
        local a1 = Instance.new("Animation"); a1.AnimationId = "rbxassetid://"..flightAnimIds.fly
        local a2 = Instance.new("Animation"); a2.AnimationId = "rbxassetid://"..flightAnimIds.idle
        return { flyTrack = animator:LoadAnimation(a1), idleTrack = animator:LoadAnimation(a2) }
    end)
    flightAnims = res and anims or nil
end

local function createFlightTouchUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "FlightControls"; sg.ResetOnSpawn = false
    local function mkBtn(name, pos, ico)
        local b = Instance.new("TextButton", sg)
        b.Name=name; b.Size=UDim2.new(0,70,0,70); b.Position=pos
        b.BackgroundColor3=Color3.new(); b.BackgroundTransparency=0.5
        b.TextColor3=Color3.new(1,1,1); b.Text=ico; b.TextSize=30
        b.Font=Enum.Font.GothamBold
        Instance.new("UICorner",b).CornerRadius=UDim.new(1,0)
        return b
    end
    local upBtn = mkBtn("UpBtn",  UDim2.new(1,-90,1,-170), "↑")
    local dnBtn = mkBtn("DnBtn",  UDim2.new(1,-90,1,-90),  "↓")
    local conns = {}
    local function bind(btn, key)
        table.insert(conns, btn.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.Touch then flightState[key]=true end
        end))
        table.insert(conns, btn.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.Touch then flightState[key]=false end
        end))
    end
    bind(upBtn,"isTouchingUp"); bind(dnBtn,"isTouchingDown")
    sg.Destroying:Connect(function()
        for _,c in ipairs(conns) do c:Disconnect() end; table.clear(conns)
    end)
    return sg
end

local function getFlightInput()
    local cam = workspace.CurrentCamera
    local char = lp.Character; if not char then return Vector3.new() end
    local hum  = char:FindFirstChild("Humanoid"); if not hum then return Vector3.new() end
    local dir, moving = Vector3.new(), false
    if UserInputService:GetFocusedTextBox() then
        if flightAnims and flightState.isMoving then
            flightState.isMoving=false; flightAnims.flyTrack:Stop(); flightAnims.idleTrack:Play()
        end
        return dir
    end
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        local md = hum.MoveDirection
        if md.Magnitude>0 then dir=md; moving=true end
        if flightState.isTouchingUp   then dir=dir+Vector3.new(0,1,0); moving=true end
        if flightState.isTouchingDown then dir=dir-Vector3.new(0,1,0); moving=true end
    else
        local look  = cam.CFrame.LookVector
        local right = cam.CFrame.RightVector
        local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
                - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
        local z = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
                - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
        if x~=0 or z~=0 then dir=right*x+look*z; moving=true end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            dir=dir+Vector3.new(0,1,0); moving=true
        end
    end
    if moving ~= flightState.isMoving and flightAnims then
        flightState.isMoving = moving
        if moving then flightAnims.idleTrack:Stop(); flightAnims.flyTrack:Play()
        else           flightAnims.flyTrack:Stop();  flightAnims.idleTrack:Play() end
    end
    if dir.Magnitude>0 then dir=dir.Unit*FlightSpeed end
    return dir
end

local function startFlight()
    if flightState.isFlying then return end
    local char=lp.Character; if not char then return end
    local hum=char:FindFirstChild("Humanoid"); if not hum then return end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    flightState.isFlying=true
    hum:SetAttribute("Flying",true)
    if flightAnims then flightAnims.idleTrack:Play() end
    hum.PlatformStand=true; hum.AutoRotate=false
    local bv=Instance.new("BodyVelocity")
    bv.Name="FlightVelocity"; bv.MaxForce=Vector3.new(1e9,1e9,1e9); bv.Parent=hrp
    local att=Instance.new("Attachment"); att.Name="FlightAttachment"; att.Parent=hrp
    local ao=Instance.new("AlignOrientation")
    ao.Name="FlightAlign"; ao.Mode=Enum.OrientationAlignmentMode.OneAttachment
    ao.Attachment0=att; ao.RigidityEnabled=false; ao.Responsiveness=15
    ao.MaxTorque=1e9; ao.Parent=hrp
    if UserInputService.TouchEnabled then
        createFlightTouchUI().Parent=lp.PlayerGui
        local tg=lp.PlayerGui:FindFirstChild("TouchGui")
        if tg then
            local jb=tg:FindFirstChild("JumpButton",true)
            if jb then jb.Visible=false end
        end
    end
    local lastTick=0
    RunService:BindToRenderStep("FioFlight",Enum.RenderPriority.Character.Value,function()
        local t=tick(); if t-lastTick<0.016 then return end; lastTick=t
        local target=getFlightInput()
        local acc=target.Magnitude>flightState.currentVelocity.Magnitude
        flightState.currentVelocity=flightState.currentVelocity:Lerp(target,acc and 0.3 or 0.2)
        bv.Velocity=flightState.currentVelocity
        if flightState.currentVelocity.Magnitude>0.1 then
            local u=flightState.currentVelocity.Unit
            local cf=CFrame.lookAt(Vector3.new(),u)
            if u.Y==0 then cf=cf*CFrame.Angles(math.rad(-15),0,0) end
            ao.CFrame=cf
        else
            ao.CFrame=CFrame.lookAt(Vector3.new(),workspace.CurrentCamera.CFrame.LookVector)
        end
    end)
end

local function stopFlight()
    if not flightState.isFlying then return end
    flightState.isFlying=false; flightState.isMoving=false
    flightState.currentVelocity=Vector3.new()
    flightState.isTouchingUp=false; flightState.isTouchingDown=false
    local char=lp.Character
    local hum=char and char:FindFirstChild("Humanoid")
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if hum then
        hum:SetAttribute("Flying",false)
        if flightAnims then flightAnims.flyTrack:Stop(); flightAnims.idleTrack:Stop() end
        hum.PlatformStand=false; hum.AutoRotate=true
    end
    RunService:UnbindFromRenderStep("FioFlight")
    if lp.PlayerGui:FindFirstChild("FlightControls") then
        lp.PlayerGui.FlightControls:Destroy()
    end
    if UserInputService.TouchEnabled then
        local tg=lp.PlayerGui:FindFirstChild("TouchGui")
        if tg then
            local jb=tg:FindFirstChild("JumpButton",true)
            if jb then jb.Visible=true end
        end
    end
    if hrp then
        for _,v in ipairs(hrp:GetChildren()) do
            if v.Name=="FlightVelocity" or v.Name=="FlightAlign"
            or v.Name=="FlightAttachment" then v:Destroy() end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
--  ATTACK SPEED  [targeted — RF.Hit InvokeServer]
--
--  Remote confirmed: ReplicatedStorage.Packages.Knit.Services
--                    .CombatService.RF.Hit  (RemoteFunction)
--  Method: InvokeServer — bukan FireServer!
--  Versi lama gagal karena semua hook check FireServer/RemoteEvent.
--
--  Sistem:
--   L1 : AnimationPlayed → AdjustSpeed sekali, zero frame cost.
--   L2 : Hook __namecall, filter exact self == _HitRemote + "InvokeServer"
--        Capture args + lockedAt.
--        Replay: _replayFlag=true → call _HitRemote:InvokeServer(patchedArgs)
--        → masuk hook lagi tapi _replayFlag skip capture → jatuh ke
--        _atkOldNC(self,...) yang execute InvokeServer asli. Tidak infinite loop.
--   Timestamp patch: scan args untuk angka mirip tick()/os.clock(), update
--        ke nilai terkini sebelum tiap replay.
-- ═══════════════════════════════════════════════════════════════

-- ── Find remote on load ───────────────────────────────────────
local _HitRemote = nil
task.spawn(function()
    local ok, r = pcall(function()
        return game:GetService("ReplicatedStorage")
            :WaitForChild("Packages",      15)
            :WaitForChild("Knit",          15)
            :WaitForChild("Services",      15)
            :WaitForChild("CombatService", 15)
            :WaitForChild("RF",            15)
            :WaitForChild("Hit",           15)
    end)
    if ok and r then
        _HitRemote  = r
        _atkDetName = "RF.Hit [ready]"
        task.delay(0.1, function()
            if atkStatLbl then
                atkStatLbl.Text      = "  ✓ RF.Hit ditemukan — siap dipakai"
                atkStatLbl.TextColor3= Color3.fromRGB(40,240,130)
            end
        end)
        print("[AtkSpeed] RF.Hit found:", r:GetFullName())
    else
        warn("[AtkSpeed] RF.Hit tidak ditemukan dalam 15s!")
        task.delay(0.1, function()
            if atkStatLbl then
                atkStatLbl.Text      = "  ✗ RF.Hit tidak ditemukan"
                atkStatLbl.TextColor3= Color3.fromRGB(255,60,60)
            end
        end)
    end
end)

-- ── Block Remote + Auto Block ─────────────────────────────────
local _BlockRemote    = nil
local AutoBlockEnabled = false
local _blockHB        = nil

task.spawn(function()
    local ok, r = pcall(function()
        return game:GetService("ReplicatedStorage")
            :WaitForChild("Packages",      15)
            :WaitForChild("Knit",          15)
            :WaitForChild("Services",      15)
            :WaitForChild("CombatService", 15)
            :WaitForChild("RF",            15)
            :WaitForChild("Block",         15)
    end)
    if ok and r then
        _BlockRemote = r
        print("[AutoBlock] RF.Block found:", r:GetFullName())
    else
        warn("[AutoBlock] RF.Block tidak ditemukan!")
    end
end)

local function enableAutoBlock()
    if _blockHB then return end
    pcall(function() _BlockRemote:InvokeServer(true) end)
    lp:SetAttribute("Blocking", true)
    _blockHB = RunService.Heartbeat:Connect(function()
        if not AutoBlockEnabled then return end
        local grabbed = lp:GetAttribute("Grabbed")
        -- Kalau lagi di-grab, spam lebih agresif pakai task.spawn
        if grabbed then
            for i = 1, 5 do
                task.spawn(function()
                    pcall(function() _BlockRemote:InvokeServer(true) end)
                end)
            end
        else
            pcall(function() _BlockRemote:InvokeServer(true) end)
        end
        lp:SetAttribute("Blocking", true)
        local char = lp.Character
        if char then char:SetAttribute("Blocking", true) end
    end)
end

local function disableAutoBlock()
    if _blockHB then _blockHB:Disconnect(); _blockHB=nil end
    pcall(function() _BlockRemote:InvokeServer(false) end)
    lp:SetAttribute("Blocking", false)
    local char = lp.Character
    if char then char:SetAttribute("Blocking", false) end
end

-- Burst block saat grabbed — aktif selalu, bukan hanya saat Immune ON
lp:GetAttributeChangedSignal("Grabbed"):Connect(function()
    if not lp:GetAttribute("Grabbed") then return end
    if not _BlockRemote then return end
    -- Burst 20x invoke saat pertama kena grab
    for i = 1, 20 do
        task.spawn(function()
            pcall(function() _BlockRemote:InvokeServer(true) end)
            lp:SetAttribute("Blocking", true)
        end)
    end
    -- Lanjut spam selama masih grabbed
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not lp:GetAttribute("Grabbed") then
            conn:Disconnect()
            return
        end
        for i = 1, 3 do
            task.spawn(function()
                pcall(function() _BlockRemote:InvokeServer(true) end)
            end)
        end
        lp:SetAttribute("Blocking", true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════
--  GRAB SYSTEM
-- ═══════════════════════════════════════════════════════════════
local _GrabRemote = nil
task.spawn(function()
    local ok, r = pcall(function()
        return game:GetService("ReplicatedStorage")
            :WaitForChild("Packages",15):WaitForChild("Knit",15)
            :WaitForChild("Services",15):WaitForChild("CombatService",15)
            :WaitForChild("RF",15):WaitForChild("Grab",15)
    end)
    if ok and r then _GrabRemote=r; print("[Grab] RF.Grab found") end
end)

-- States
local NoGrabCool      = false
local AutoGrabEnabled = false
local _grabHB         = nil

local function startGrabLoop()
    if _grabHB then return end
    _grabHB = RunService.Heartbeat:Connect(function()
        local char = lp.Character; if not char then return end
        if NoGrabCool then
            if lp:GetAttribute("GrabCool") then
                lp:SetAttribute("GrabCool", false)
            end
        end
        if AutoGrabEnabled and _GrabRemote then
            local tgt = currentTarget
            if tgt and tgt.Character then
                pcall(function() _GrabRemote:InvokeServer(tgt) end)
            else
                pcall(function() _GrabRemote:InvokeServer() end)
            end
        end
    end)
end

local function stopGrabLoopIfIdle()
    if NoGrabCool or AutoGrabEnabled then return end
    if _grabHB then _grabHB:Disconnect(); _grabHB=nil end
end

-- ── L1: Event-driven anim boost ──────────────────────────────
local _animConn = nil
local function _connectAnimBoost()
    if _animConn then _animConn:Disconnect(); _animConn=nil end
    local char = lp.Character; if not char then return end
    local hum  = char:FindFirstChild("Humanoid"); if not hum then return end
    local anim = hum:FindFirstChildOfClass("Animator"); if not anim then return end
    _animConn = anim.AnimationPlayed:Connect(function(track)
        if not AtkSpeedEnabled or track.Looped then return end
        pcall(function() track:AdjustSpeed(AtkSpeedMult) end)
        track.Stopped:Connect(function()
            pcall(function() track:AdjustSpeed(1) end)
        end)
    end)
end

local function _disconnectAnimBoost()
    if _animConn then _animConn:Disconnect(); _animConn=nil end
    pcall(function()
        local char = lp.Character; if not char then return end
        local hum  = char:FindFirstChild("Humanoid"); if not hum then return end
        local anim = hum:FindFirstChildOfClass("Animator"); if not anim then return end
        for _, tr in ipairs(anim:GetPlayingAnimationTracks()) do
            if not tr.Looped then pcall(function() tr:AdjustSpeed(1) end) end
        end
    end)
end

-- ── L2: Hook CombatClient punch — bypass debounce 0.35s ─────
-- CombatClient pakai v_u_27 (lastHitTick) cek tick()-v_u_27 < 0.35
-- Kita hook __namecall: setiap :Hit() → auto spam ulang via task.spawn
-- tanpa lewat debounce client karena kita panggil langsung ke remote
local _capture     = nil
local _replayFlag  = false
local _replayAccum = 0
local _replayHB    = nil

-- Patch timestamp args sebelum replay
local function _patchTimestamps(argsPacked)
    local nt = tick()
    local nc = os.clock()
    local out = { n = argsPacked.n }
    for i = 1, argsPacked.n do
        local v = argsPacked[i]
        if type(v) == "number" then
            if     v >= nc - 120 and v <= nc + 2 then out[i] = nc
            elseif v >= nt - 120 and v <= nt + 2 then out[i] = nt
            else                                       out[i] = v  end
        else
            out[i] = v
        end
    end
    return out
end

-- Replay loop: tiap Heartbeat langsung fire Hit remote, bypass client debounce
local function _startReplayLoop()
    if _replayHB then return end
    _replayHB = RunService.Heartbeat:Connect(function()
        if not AtkSpeedEnabled then return end
        if not _capture        then return end
        if not _HitRemote      then return end
        local pa = _patchTimestamps(_capture.args)
        _replayFlag = true
        -- task.spawn biar tidak blocking, fire sebanyak AtkSpeedMult kali per frame
        for i = 1, math.max(1, AtkSpeedMult) do
            task.spawn(function()
                pcall(function()
                    _HitRemote:InvokeServer(table.unpack(pa, 1, pa.n))
                end)
            end)
        end
        _replayFlag = false
    end)
end

local function _stopReplayLoop()
    if _replayHB then _replayHB:Disconnect(); _replayHB=nil end
    _capture = nil; _replayAccum = 0; _replayFlag = false
end

local function _enableAtkNamecall()
    if _atkOldNC then return end
    local ok = pcall(function()
        _atkMT    = getrawmetatable(game)
        _atkOldNC = _atkMT.__namecall
        setreadonly(_atkMT, false)
        _atkMT.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()

            -- Capture HANYA dari RF.Hit + InvokeServer + bukan replay kita
            if not _replayFlag
               and AtkSpeedEnabled
               and method == "InvokeServer"
               and self == _HitRemote
            then
                local now = os.clock()
                _capture = {
                    args     = table.pack(...),
                    lockedAt = now,
                }
                if atkStatLbl then
                    atkStatLbl.Text      = "  ⚡ Replaying RF.Hit x"..AtkSpeedMult
                    atkStatLbl.TextColor3= Color3.fromRGB(255,140,30)
                end
            end

            return _atkOldNC(self, ...)
        end)
        setreadonly(_atkMT, true)
    end)
    if not ok then
        warn("[AtkSpeed] __namecall hook gagal.")
        if atkStatLbl then
            atkStatLbl.Text      = "  ✗ Hook gagal — coba executor lain"
            atkStatLbl.TextColor3= Color3.fromRGB(255,60,60)
        end
    end
end

local function _disableAtkNamecall()
    pcall(function()
        if _atkMT and _atkOldNC then
            setreadonly(_atkMT, false)
            _atkMT.__namecall = _atkOldNC
            setreadonly(_atkMT, true)
        end
    end)
    _atkOldNC = nil
end

-- Master enable/disable
local function enableAtkSpeed()
    _capture = nil
    _connectAnimBoost()
    _enableAtkNamecall()
    _startReplayLoop()
    if atkStatLbl then
        if _HitRemote then
            atkStatLbl.Text      = "  ✓ RF.Hit siap — mukul musuh!"
            atkStatLbl.TextColor3= Color3.fromRGB(40,240,130)
        else
            atkStatLbl.Text      = "  ⏳ Mencari RF.Hit..."
            atkStatLbl.TextColor3= Color3.fromRGB(0,220,255)
        end
    end
end

local function disableAtkSpeed()
    _disconnectAnimBoost()
    _stopReplayLoop()
    _disableAtkNamecall()
    if atkStatLbl then
        atkStatLbl.Text      = "  Remote: RF.Hit"
        atkStatLbl.TextColor3= Color3.fromRGB(110,110,155)
    end
end

lp.CharacterAdded:Connect(function()
    task.wait(1)
    _capture = nil   -- stale Instance refs di args → invalid setelah respawn
    if AtkSpeedEnabled then
        _connectAnimBoost()
        if atkStatLbl then
            atkStatLbl.Text      = "  ⏸ Respawn — mukul lagi untuk mulai"
            atkStatLbl.TextColor3= Color3.fromRGB(110,110,155)
        end
    end
end)



-- ═══════════════════════════════════════════
--  HITBOX STATE
-- ═══════════════════════════════════════════
local origSizes={};local origTrans={};local origCC={};local expanded={}
local ownSize=nil;local ownTrans=nil

-- ═══════════════════════════════════════════════════════════════
--  CYBERPUNK NEON PALETTE
-- ═══════════════════════════════════════════════════════════════
local C = {
    -- Backgrounds — dark navy/space
    bg0   = Color3.fromRGB(4,   4,  12),
    bg1   = Color3.fromRGB(7,   7,  18),
    bg2   = Color3.fromRGB(11,  11, 26),
    bg3   = Color3.fromRGB(16,  16, 36),
    bgCard= Color3.fromRGB(10,  10, 22),

    -- Neon Purple (primary)
    p0    = Color3.fromRGB(100, 20, 200),
    p1    = Color3.fromRGB(140, 50, 240),
    p2    = Color3.fromRGB(185, 90, 255),
    pDim  = Color3.fromRGB(28,  8,  52),
    pGlow = Color3.fromRGB(160, 60, 255),

    -- Neon Cyan (secondary)
    cy0   = Color3.fromRGB(0,   180, 210),
    cy1   = Color3.fromRGB(0,   220, 255),
    cy2   = Color3.fromRGB(80,  240, 255),
    cyDim = Color3.fromRGB(0,   34,  44),

    -- Neon Pink
    pk0   = Color3.fromRGB(220, 30,  120),
    pk1   = Color3.fromRGB(255, 60,  160),
    pk2   = Color3.fromRGB(255, 110, 195),
    pkDim = Color3.fromRGB(44,  5,   24),

    -- Neon Green
    gn0   = Color3.fromRGB(20,  200, 100),
    gn1   = Color3.fromRGB(40,  240, 130),
    gn2   = Color3.fromRGB(100, 255, 170),
    gnDim = Color3.fromRGB(5,   38,  18),

    -- Neon Yellow/Gold
    yl0   = Color3.fromRGB(220, 180, 0),
    yl1   = Color3.fromRGB(255, 215, 20),
    ylDim = Color3.fromRGB(40,  34,  0),

    -- Neon Orange
    or0   = Color3.fromRGB(220, 100, 0),
    or1   = Color3.fromRGB(255, 140, 30),
    orDim = Color3.fromRGB(44,  20,  0),

    -- Text
    t0    = Color3.fromRGB(60,  60,  90),
    t1    = Color3.fromRGB(110, 110, 155),
    t2    = Color3.fromRGB(175, 175, 215),
    white = Color3.fromRGB(230, 230, 255),

    -- Borders
    border= Color3.fromRGB(30,  30,  55),
    glow  = Color3.fromRGB(130, 50,  220),
}

-- ═══════════════════════════════════════════
--  LAYOUT
-- ═══════════════════════════════════════════
local W        = 205
local H        = 405
local HDR_H    = 42
local INFO_H   = 22
local TAB_H    = 34
local CONT_TOP = HDR_H + INFO_H + 5
local CONT_H   = H - CONT_TOP - TAB_H - 4
local TAB_Y    = H - TAB_H - 3

-- ═══════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════
local function cr(inst, r)
    Instance.new("UICorner", inst).CornerRadius = UDim.new(0, r or 7)
end
local function sk(inst, col, t, tr)
    local s = Instance.new("UIStroke", inst)
    s.Color=col; s.Thickness=t or 1; s.Transparency=tr or 0.3
    return s
end
local function tx(par, txt, sz, col, fnt, zi)
    local l = Instance.new("TextLabel", par)
    l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=col or C.t1
    l.Font=fnt or Enum.Font.GothamSemibold; l.TextSize=sz or 11; l.ZIndex=zi or 5
    return l
end

-- Cyberpunk pill button dengan glow effect
local function pill(par, y, h, txt, tcol, bg, glowCol)
    local b = Instance.new("TextButton", par)
    b.Size             = UDim2.new(1,-12,0, h or 30)
    b.Position         = UDim2.new(0, 6, 0, y)
    b.BackgroundColor3 = bg or C.bg2
    b.Text             = txt
    b.TextColor3       = tcol or C.t1
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 11
    b.AutoButtonColor  = false
    b.ZIndex           = 5
    cr(b, 8)
    -- Accent left bar
    local bar = Instance.new("Frame", b)
    bar.Size             = UDim2.new(0, 2, 0.55, 0)
    bar.Position         = UDim2.new(0, 0, 0.225, 0)
    bar.BackgroundColor3 = glowCol or tcol or C.p1
    bar.ZIndex           = 6
    cr(bar, 2)
    return b
end

-- Number row card
local function numRow(par, y, ico, lbtx, col, val)
    local card = Instance.new("Frame", par)
    card.Size             = UDim2.new(1,-12,0,38)
    card.Position         = UDim2.new(0, 6, 0, y)
    card.BackgroundColor3 = C.bgCard
    card.ZIndex           = 5
    cr(card, 8)
    -- Top glow line
    local topLine = Instance.new("Frame", card)
    topLine.Size             = UDim2.new(1, 0, 0, 1)
    topLine.BackgroundColor3 = col
    topLine.BackgroundTransparency = 0.6
    topLine.ZIndex           = 6
    -- Label
    local lb = tx(card, ico.."  "..lbtx, 10, col, Enum.Font.GothamBold, 6)
    lb.Size=UDim2.new(0.5,0,1,0); lb.Position=UDim2.new(0,10,0,0)
    lb.TextXAlignment=Enum.TextXAlignment.Left
    -- Buttons
    local function mkB(xOff, t2, bg2, tc2)
        local b = Instance.new("TextButton", card)
        b.Size=UDim2.new(0,24,0,22); b.Position=UDim2.new(1,xOff,0.5,-11)
        b.BackgroundColor3=bg2; b.Text=t2; b.TextColor3=tc2
        b.Font=Enum.Font.GothamBlack; b.TextSize=16
        b.AutoButtonColor=false; b.ZIndex=6; cr(b,6)
        return b
    end
    local minus = mkB(-80,"−", Color3.fromRGB(30,5,5),   Color3.fromRGB(255,60,60))
    local valL  = Instance.new("TextLabel", card)
    valL.Size=UDim2.new(0,34,0,22); valL.Position=UDim2.new(1,-52,0.5,-11)
    valL.BackgroundColor3=C.bg0; valL.Text=tostring(val)
    valL.TextColor3=C.white; valL.Font=Enum.Font.GothamBlack
    valL.TextSize=11; valL.ZIndex=6; cr(valL,5)
    local plus  = mkB(-26,"+", Color3.fromRGB(5,30,10),  Color3.fromRGB(50,230,100))
    sk(card, col, 1, 0.65)
    return minus, valL, plus
end

-- Section header with neon line
local function sec(par, y, txt, col)
    col = col or C.p1
    local row = Instance.new("Frame", par)
    row.Size=UDim2.new(1,-12,0,18); row.Position=UDim2.new(0,6,0,y)
    row.BackgroundTransparency=1; row.ZIndex=5
    local l1=Instance.new("Frame",row)
    l1.Size=UDim2.new(0.15,0,0,1); l1.Position=UDim2.new(0,0,0.5,0)
    l1.BackgroundColor3=col; l1.BackgroundTransparency=0.4; l1.ZIndex=6
    local t=tx(row,txt,8,col,Enum.Font.GothamBold,6)
    t.Size=UDim2.new(0.7,0,1,0); t.Position=UDim2.new(0.15,0,0,0)
    t.TextXAlignment=Enum.TextXAlignment.Center
    local l2=Instance.new("Frame",row)
    l2.Size=UDim2.new(0.15,0,0,1); l2.Position=UDim2.new(0.85,0,0.5,0)
    l2.BackgroundColor3=col; l2.BackgroundTransparency=0.4; l2.ZIndex=6
end

-- ═══════════════════════════════════════════════════════════════
--  SCREEN GUI — CYBERPUNK NEON THEME
-- ═══════════════════════════════════════════════════════════════
local Gui = Instance.new("ScreenGui")
Gui.ResetOnSpawn=false; Gui.DisplayOrder=99; Gui.IgnoreGuiInset=true
Gui.Parent=lp:WaitForChild("PlayerGui")

-- Outer purple glow
local Glow = Instance.new("Frame", Gui)
Glow.Size=UDim2.new(0,W+16,0,H+16); Glow.Position=UDim2.new(1,-(W+13),0,40)
Glow.BackgroundColor3=C.p1; Glow.BackgroundTransparency=0.82; Glow.ZIndex=1
cr(Glow, 16)

-- Second glow layer (cyan tint)
local Glow2 = Instance.new("Frame", Gui)
Glow2.Size=UDim2.new(0,W+6,0,H+6); Glow2.Position=UDim2.new(1,-(W+8),0,43)
Glow2.BackgroundColor3=C.cy1; Glow2.BackgroundTransparency=0.92; Glow2.ZIndex=1
cr(Glow2, 14)

-- Main frame
local Frame = Instance.new("Frame", Gui)
Frame.Size=UDim2.new(0,W,0,H); Frame.Position=UDim2.new(1,-(W+5),0,46)
Frame.BackgroundColor3=C.bg1; Frame.ZIndex=2; Frame.ClipsDescendants=false
cr(Frame, 12)
-- Main border: neon purple
sk(Frame, C.p1, 1.2, 0.2)

-- Top accent gradient bar (purple → cyan)
local acc1 = Instance.new("Frame", Frame)
acc1.Size=UDim2.new(0.5,0,0,2); acc1.BackgroundColor3=C.p2; acc1.ZIndex=4
local acc2 = Instance.new("Frame", Frame)
acc2.Size=UDim2.new(0.5,0,0,2); acc2.Position=UDim2.new(0.5,0,0,0)
acc2.BackgroundColor3=C.cy1; acc2.ZIndex=4

-- ── HEADER ──────────────────────────────────────────
local Hdr = Instance.new("Frame", Frame)
Hdr.Size=UDim2.new(1,0,0,HDR_H); Hdr.BackgroundColor3=C.bg0; Hdr.ZIndex=3
cr(Hdr, 12)

-- Animated glitch dot (left)
local dot = Instance.new("Frame", Hdr)
dot.Size=UDim2.new(0,7,0,7); dot.Position=UDim2.new(0,10,0.5,-3.5)
dot.BackgroundColor3=C.p2; dot.ZIndex=7; cr(dot,99)
-- Pulse ring
local ring = Instance.new("Frame", Hdr)
ring.Size=UDim2.new(0,14,0,14); ring.Position=UDim2.new(0,6.5,0.5,-7)
ring.BackgroundColor3=C.p1; ring.BackgroundTransparency=0.65; ring.ZIndex=5; cr(ring,99)

-- Title: FIO AURA
local titleTx = tx(Hdr,"FIO AURA",15,C.p2,Enum.Font.GothamBlack,6)
titleTx.Size=UDim2.new(0,95,1,0); titleTx.Position=UDim2.new(0,24,0,0)
titleTx.TextXAlignment=Enum.TextXAlignment.Left

-- Version badge
local verBadge = Instance.new("Frame", Hdr)
verBadge.Size=UDim2.new(0,32,0,15); verBadge.Position=UDim2.new(0,98,0.5,-7.5)
verBadge.BackgroundColor3=C.pDim; verBadge.ZIndex=6; cr(verBadge,4)
sk(verBadge, C.p1, 1, 0.4)
local verTx = tx(verBadge,"v6.4",8,C.cy1,Enum.Font.GothamBlack,7)
verTx.Size=UDim2.new(1,0,1,0); verTx.TextXAlignment=Enum.TextXAlignment.Center

-- Subtitle
local subTx = tx(Hdr,"CYBER EDITION",7,C.cy0,Enum.Font.GothamBold,5)
subTx.Size=UDim2.new(0,110,0,10); subTx.Position=UDim2.new(0,24,1,-13)
subTx.TextXAlignment=Enum.TextXAlignment.Left

-- Header bottom divider
local hDiv = Instance.new("Frame", Hdr)
hDiv.Size=UDim2.new(1,0,0,1); hDiv.Position=UDim2.new(0,0,1,-1)
hDiv.BackgroundColor3=C.p0; hDiv.BackgroundTransparency=0.3; hDiv.ZIndex=4

-- Minimize btn
local MinBtn = Instance.new("TextButton", Hdr)
MinBtn.Size=UDim2.new(0,24,0,22); MinBtn.Position=UDim2.new(1,-30,0.5,-11)
MinBtn.BackgroundColor3=C.pDim; MinBtn.Text="—"; MinBtn.TextColor3=C.p2
MinBtn.Font=Enum.Font.GothamBlack; MinBtn.TextSize=13
MinBtn.AutoButtonColor=false; MinBtn.ZIndex=7; cr(MinBtn,6)
sk(MinBtn, C.p1, 1, 0.45)

-- Pulse animation on dot
task.spawn(function()
    while true do
        TweenService:Create(ring, TweenInfo.new(0.9,Enum.EasingStyle.Sine), {BackgroundTransparency=0.9, Size=UDim2.new(0,18,0,18), Position=UDim2.new(0,4.5,0.5,-9)}):Play()
        task.wait(0.9)
        TweenService:Create(ring, TweenInfo.new(0.9,Enum.EasingStyle.Sine), {BackgroundTransparency=0.6, Size=UDim2.new(0,14,0,14), Position=UDim2.new(0,6.5,0.5,-7)}):Play()
        task.wait(0.9)
    end
end)

-- ── INFO BAR ────────────────────────────────────────
local Info = Instance.new("Frame", Frame)
Info.Size=UDim2.new(1,-10,0,INFO_H); Info.Position=UDim2.new(0,5,0,HDR_H+3)
Info.BackgroundColor3=C.bg0; Info.ZIndex=3; cr(Info,6)
sk(Info, C.p0, 1, 0.45)

-- Neon top line on info bar
local iLine = Instance.new("Frame", Info)
iLine.Size=UDim2.new(1,0,0,1); iLine.BackgroundColor3=C.p1
iLine.BackgroundTransparency=0.5; iLine.ZIndex=5

local KillL = tx(Info,"⚔ K:···",10,C.pk1,Enum.Font.GothamBlack,4)
KillL.Size=UDim2.new(0.35,0,1,0); KillL.Position=UDim2.new(0,6,0,0)
KillL.TextXAlignment=Enum.TextXAlignment.Left

local HpL = tx(Info,"♥ ---",9,C.gn1,Enum.Font.GothamBold,4)
HpL.Size=UDim2.new(0.36,0,1,0); HpL.Position=UDim2.new(0.35,0,0,0)
HpL.TextXAlignment=Enum.TextXAlignment.Center

local TimeL = tx(Info,"··:··",9,C.cy0,Enum.Font.Gotham,4)
TimeL.Size=UDim2.new(0.29,-4,1,0); TimeL.Position=UDim2.new(0.71,0,0,0)
TimeL.TextXAlignment=Enum.TextXAlignment.Right

local function updateHp()
    local c=lp.Character; if not c then HpL.Text="♥ ---";return end
    local h=c:FindFirstChild("Humanoid"); if not h then HpL.Text="♥ ---";return end
    local pct=math.floor((h.Health/math.max(h.MaxHealth,1))*100)
    if pct>60 then HpL.TextColor3=C.gn1
    elseif pct>30 then HpL.TextColor3=C.yl1
    else HpL.TextColor3=C.pk1 end
    HpL.Text="♥ "..pct.."%"
end
task.spawn(function() while task.wait(0.25) do updateHp() end end)
task.spawn(function() while task.wait(1) do TimeL.Text=os.date("%H:%M") end end)
task.spawn(function()
    local ls=lp:WaitForChild("leaderstats",10)
    if ls then
        local k=ls:FindFirstChild("Kills") or ls:FindFirstChild("kills")
        if k then
            KillL.Text="⚔ K:"..k.Value
            k:GetPropertyChangedSignal("Value"):Connect(function()
                KillL.Text="⚔ K:"..k.Value
            end)
        end
    end
end)

-- ── TAB BAR ─────────────────────────────────────────
local TabBar = Instance.new("Frame", Frame)
TabBar.Size=UDim2.new(1,-10,0,TAB_H); TabBar.Position=UDim2.new(0,5,0,TAB_Y)
TabBar.BackgroundColor3=C.bg0; TabBar.ZIndex=4; cr(TabBar,8)
sk(TabBar, C.border, 1, 0.1)

local PHolder = Instance.new("Frame", Frame)
PHolder.Size=UDim2.new(1,0,0,CONT_H); PHolder.Position=UDim2.new(0,0,0,CONT_TOP)
PHolder.BackgroundTransparency=1; PHolder.ClipsDescendants=true; PHolder.ZIndex=3

-- ─── TABS ────────────────────────────────────────────
local TABS = {
    {ico="⚔", nm="Combat"},
    {ico="🎯",nm="Target"},
    {ico="🏃",nm="Move"},
    {ico="⚙", nm="Config"},
}
local pages={};local tBtns={};local curTab=1

for i=1,#TABS do
    local pg=Instance.new("ScrollingFrame",PHolder)
    pg.Size=UDim2.new(1,0,1,0); pg.BackgroundTransparency=1
    pg.ScrollBarThickness=2; pg.ScrollBarImageColor3=C.p1
    pg.CanvasSize=UDim2.new(0,0,0,0); pg.ScrollingDirection=Enum.ScrollingDirection.Y
    pg.ElasticBehavior=Enum.ElasticBehavior.Never; pg.ZIndex=4; pg.Visible=(i==1)
    pages[i]=pg
end

local tw=1/#TABS
for i,t in ipairs(TABS) do
    local b=Instance.new("TextButton",TabBar)
    b.Size=UDim2.new(tw,-3,1,-6); b.Position=UDim2.new(tw*(i-1),1.5,0,3)
    b.BackgroundColor3=(i==1) and C.pDim or C.bg0
    b.Text=t.ico.."\n"..t.nm
    b.TextColor3=(i==1) and C.p2 or C.t0
    b.Font=Enum.Font.GothamBold; b.TextSize=8; b.AutoButtonColor=false; b.ZIndex=6; cr(b,6)
    if i==1 then sk(b,C.p1,1,0.4) end
    tBtns[i]=b
end

local tStrokes={};tStrokes[1]=tBtns[1]:FindFirstChildOfClass("UIStroke")
local function switchTab(idx)
    curTab=idx
    for i,pg in ipairs(pages) do pg.Visible=(i==idx) end
    for i,b in ipairs(tBtns) do
        if i==idx then
            b.BackgroundColor3=C.pDim; b.TextColor3=C.p2
            if not tStrokes[i] then tStrokes[i]=sk(b,C.p1,1,0.4) end
        else
            b.BackgroundColor3=C.bg0; b.TextColor3=C.t0
            if tStrokes[i] then tStrokes[i]:Destroy(); tStrokes[i]=nil end
        end
    end
end
for i=1,#TABS do local idx=i tBtns[i].MouseButton1Click:Connect(function() switchTab(idx) end) end

-- ═══════════════════════════════════════════════════════════════
--  PAGE 1 — COMBAT
-- ═══════════════════════════════════════════════════════════════
local P1=pages[1]; local y1=7

-- ── FIO AURA MODE (Attack Speed) — paling atas ───────────────
sec(P1,y1,"FIO AURA MODE",C.or1); y1=y1+23

local AtkSpeedBtn=Instance.new("TextButton",P1)
AtkSpeedBtn.Size=UDim2.new(1,-12,0,42); AtkSpeedBtn.Position=UDim2.new(0,6,0,y1)
AtkSpeedBtn.BackgroundColor3=C.bg0
AtkSpeedBtn.Text="🥊  FIO AURA MODE  ·  OFF"
AtkSpeedBtn.TextColor3=C.or1; AtkSpeedBtn.Font=Enum.Font.GothamBlack; AtkSpeedBtn.TextSize=12
AtkSpeedBtn.AutoButtonColor=false; AtkSpeedBtn.ZIndex=5; cr(AtkSpeedBtn,9)
local atkSpeedSK=sk(AtkSpeedBtn,C.or1,1.5,0.35)
local atkLine=Instance.new("Frame",AtkSpeedBtn)
atkLine.Size=UDim2.new(1,0,0,2); atkLine.Position=UDim2.new(0,0,1,-2)
atkLine.BackgroundColor3=C.or1; atkLine.BackgroundTransparency=0.4; atkLine.ZIndex=6
y1=y1+49

-- Speed multiplier numRow
local atkM,atkV,atkP=numRow(P1,y1,"⚡","Hit Speed (x)",C.or1,AtkSpeedMult); y1=y1+44

-- Status indicator
local atkStatCard=Instance.new("Frame",P1)
atkStatCard.Size=UDim2.new(1,-12,0,28); atkStatCard.Position=UDim2.new(0,6,0,y1)
atkStatCard.BackgroundColor3=C.bg0; atkStatCard.ZIndex=5; cr(atkStatCard,6)
sk(atkStatCard,C.or0,1,0.5)
local atkStatLbl=tx(atkStatCard,"  Remote: none detected",9,C.t1,Enum.Font.Gotham,6)
atkStatLbl.Size=UDim2.new(1,0,1,0); atkStatLbl.TextXAlignment=Enum.TextXAlignment.Left
y1=y1+35

-- AURA — hero button
sec(P1,y1,"AURA",C.cy1); y1=y1+23
local AuraBtn = Instance.new("TextButton", P1)
AuraBtn.Size=UDim2.new(1,-12,0,42); AuraBtn.Position=UDim2.new(0,6,0,y1)
AuraBtn.BackgroundColor3=C.bg0; AuraBtn.Text="⚡  MANUAL AURA  ·  OFF"
AuraBtn.TextColor3=C.cy1; AuraBtn.Font=Enum.Font.GothamBlack; AuraBtn.TextSize=12
AuraBtn.AutoButtonColor=false; AuraBtn.ZIndex=5; cr(AuraBtn,9)
local auraSK = sk(AuraBtn, C.cy1, 1.5, 0.35)
local auraLine = Instance.new("Frame", AuraBtn)
auraLine.Size=UDim2.new(1,0,0,2); auraLine.Position=UDim2.new(0,0,1,-2)
auraLine.BackgroundColor3=C.cy1; auraLine.BackgroundTransparency=0.3; auraLine.ZIndex=6
y1=y1+49

sec(P1,y1,"COMBAT",C.cy1); y1=y1+23

local AutoBtn = pill(P1,y1,30,"🎯  AUTO TARGET  ·  ON",  C.gn1,C.gnDim,C.gn1)
local autoSK  = sk(AutoBtn,C.gn1,1,0.55); y1=y1+35
local OrbitBtn= pill(P1,y1,30,"🔄  ORBIT LOCK  ·  OFF",   C.cy1,C.bg2, C.cy1)
local orbitSK = sk(OrbitBtn,C.border,1,0.5); y1=y1+35
local FloatBtn= pill(P1,y1,30,"🕊  FLOAT ABOVE  ·  OFF",  C.p2, C.bg2, C.p2)
local floatSK = sk(FloatBtn,C.border,1,0.5); y1=y1+38

sec(P1,y1,"SURVIVAL",C.p2); y1=y1+23

local ARBtn       = pill(P1,y1,30,"🦴  ANTI RAGDOLL  ·  OFF", C.cy2, C.bg2, C.cy2)
local arSK        = sk(ARBtn,C.border,1,0.5); y1=y1+35
local AlwaysRagBtn= pill(P1,y1,30,"💀  ALWAYS RAGDOLL  ·  OFF",C.pk2,C.bg2, C.pk2)
local alwRagSK    = sk(AlwaysRagBtn,C.border,1,0.5); y1=y1+35
local AntiAuraBtn = pill(P1,y1,30,"🌀  ANTI AURA  ·  OFF",C.or1,C.bg2,C.or1)
local antiAuraSK  = sk(AntiAuraBtn,C.border,1,0.5); y1=y1+38

P1.CanvasSize=UDim2.new(0,0,0,y1+6)

-- ═══════════════════════════════════════════════════════════════
--  PAGE 2 — TARGET
-- ═══════════════════════════════════════════════════════════════
local P2=pages[2]; local y2=7

-- Status card (neon gold)
local StatCard=Instance.new("Frame",P2)
StatCard.Size=UDim2.new(1,-12,0,32); StatCard.Position=UDim2.new(0,6,0,y2)
StatCard.BackgroundColor3=C.bg0; StatCard.ZIndex=5; cr(StatCard,7)
sk(StatCard,C.yl0,1,0.35)
local sCardLine=Instance.new("Frame",StatCard)
sCardLine.Size=UDim2.new(0,2,0.6,0); sCardLine.Position=UDim2.new(0,0,0.2,0)
sCardLine.BackgroundColor3=C.yl1; sCardLine.ZIndex=6; cr(sCardLine,2)
local StatLbl=tx(StatCard,"  Target: None",11,C.yl1,Enum.Font.GothamBold,6)
StatLbl.Size=UDim2.new(1,0,1,0); StatLbl.TextXAlignment=Enum.TextXAlignment.Left
y2=y2+38

sec(P2,y2,"PLAYER LIST",C.cy1); y2=y2+23

local LScroll=Instance.new("ScrollingFrame",P2)
LScroll.Size=UDim2.new(1,-12,0,185); LScroll.Position=UDim2.new(0,6,0,y2)
LScroll.BackgroundColor3=C.bg0; LScroll.ScrollBarThickness=2
LScroll.ScrollBarImageColor3=C.p1; LScroll.ElasticBehavior=Enum.ElasticBehavior.Never
LScroll.ZIndex=5; cr(LScroll,7); sk(LScroll,C.border,1,0.15)
local LLayout=Instance.new("UIListLayout",LScroll); LLayout.Padding=UDim.new(0,2)
local LPad=Instance.new("UIPadding",LScroll)
LPad.PaddingLeft=UDim.new(0,3); LPad.PaddingRight=UDim.new(0,3); LPad.PaddingTop=UDim.new(0,3)
y2=y2+190; P2.CanvasSize=UDim2.new(0,0,0,y2+4)

-- ═══════════════════════════════════════════════════════════════
--  PAGE 3 — MOVEMENT
-- ═══════════════════════════════════════════════════════════════
local P3=pages[3]; local y3=7
sec(P3,y3,"WALK SPEED",C.cy1); y3=y3+23
local spdM,spdV,spdP=numRow(P3,y3,"⚡","Walk Speed",C.cy1,CurrentSpeed); y3=y3+44
sec(P3,y3,"FLOAT HEIGHT",C.p2); y3=y3+23
local fltM,fltV,fltP=numRow(P3,y3,"🕊","Float Height",C.p2,FloatHeight); y3=y3+44
local fn=tx(P3,"studs di atas kepala target",8,C.t0,Enum.Font.Gotham,5)
fn.Size=UDim2.new(1,-12,0,14); fn.Position=UDim2.new(0,6,0,y3)
fn.TextXAlignment=Enum.TextXAlignment.Center; y3=y3+22
P3.CanvasSize=UDim2.new(0,0,0,y3+4)

-- ═══════════════════════════════════════════════════════════════
--  PAGE 4 — CONFIG
-- ═══════════════════════════════════════════════════════════════
local P4=pages[4]; local y4=7
sec(P4,y4,"HITBOX & RANGE",C.pk1); y4=y4+23
local hbM,hbV,hbP=numRow(P4,y4,"📦","Hitbox Size",C.pk1,HitboxSize); y4=y4+44
local rnM,rnV,rnP=numRow(P4,y4,"📡","Auto Range", C.yl1,Range);     y4=y4+48
sec(P4,y4,"ORBIT",C.cy1); y4=y4+23
local orRM,orRV,orRP=numRow(P4,y4,"🌀","Orbit Radius",C.cy1,orbitRadius); y4=y4+44
local orSM,orSV,orSP=numRow(P4,y4,"💨","Orbit Speed", C.p2, orbitSpeed);  y4=y4+48
sec(P4,y4,"RESET",C.t1); y4=y4+23
local RstBtn=pill(P4,y4,28,"↺  Reset Speed → 25",C.t2,C.bg2,C.t2)
sk(RstBtn,C.border,1,0.4); y4=y4+34

sec(P4,y4,"DEFENSE",C.gn1); y4=y4+23
do
local AutoBlockBtn=Instance.new("TextButton",P4)
AutoBlockBtn.Size=UDim2.new(1,-12,0,42); AutoBlockBtn.Position=UDim2.new(0,6,0,y4)
AutoBlockBtn.BackgroundColor3=C.bg0; AutoBlockBtn.Text="🛡  IMMUNE  ·  OFF"
AutoBlockBtn.TextColor3=C.gn1; AutoBlockBtn.Font=Enum.Font.GothamBlack; AutoBlockBtn.TextSize=12
AutoBlockBtn.AutoButtonColor=false; AutoBlockBtn.ZIndex=5; cr(AutoBlockBtn,9)
local abSK=sk(AutoBlockBtn,C.gn1,1.5,0.4)
local abLine=Instance.new("Frame",AutoBlockBtn)
abLine.Size=UDim2.new(1,0,0,2); abLine.Position=UDim2.new(0,0,1,-2)
abLine.BackgroundColor3=C.gn1; abLine.BackgroundTransparency=0.4; abLine.ZIndex=6
y4=y4+49
do local abNote=tx(P4,"Kirim RF.Block=true terus menerus",8,C.t0,Enum.Font.Gotham,5); abNote.Size=UDim2.new(1,-12,0,14); abNote.Position=UDim2.new(0,6,0,y4); abNote.TextXAlignment=Enum.TextXAlignment.Center end
y4=y4+20

AutoBlockBtn.Activated:Connect(function()
    AutoBlockEnabled = not AutoBlockEnabled
    if AutoBlockEnabled then
        AutoBlockBtn.Text="🛡  IMMUNE  ·  ON"; AutoBlockBtn.TextColor3=C.gn1
        AutoBlockBtn.BackgroundColor3=C.gnDim; abSK.Color=C.gn1; abSK.Transparency=0.2
        abLine.BackgroundTransparency=0.2; enableAutoBlock()
    else
        AutoBlockBtn.Text="🛡  IMMUNE  ·  OFF"; AutoBlockBtn.TextColor3=C.gn1
        AutoBlockBtn.BackgroundColor3=C.bg0; abSK.Color=C.gn1; abSK.Transparency=0.4
        abLine.BackgroundTransparency=0.4; disableAutoBlock()
    end
end)
end

sec(P4,y4,"FIGHTING STYLE",C.yl1); y4=y4+23
do
local FS={"Default","Leg Kick","Midnight Blade","Gojo","Spiderman","Guard","Wanda","Ultra Goku","Headless Horseman"}
local fi=1
local fsCard=Instance.new("Frame",P4)
fsCard.Size=UDim2.new(1,-12,0,38); fsCard.Position=UDim2.new(0,6,0,y4)
fsCard.BackgroundColor3=C.bg0; fsCard.ZIndex=5; cr(fsCard,8); sk(fsCard,C.yl1,1.2,0.35)
local fsLbl=tx(fsCard,"⚔ "..FS[fi],12,C.yl1,Enum.Font.GothamBlack,6)
fsLbl.Size=UDim2.new(1,-70,1,0); fsLbl.Position=UDim2.new(0,8,0,0)
fsLbl.TextXAlignment=Enum.TextXAlignment.Left
local fsPrev=Instance.new("TextButton",fsCard)
fsPrev.Size=UDim2.new(0,30,0,26); fsPrev.Position=UDim2.new(1,-64,0.5,-13)
fsPrev.BackgroundColor3=C.bg1; fsPrev.Text="◀"; fsPrev.TextColor3=C.yl1
fsPrev.Font=Enum.Font.GothamBold; fsPrev.TextSize=12; fsPrev.ZIndex=7; cr(fsPrev,6)
local fsNext=Instance.new("TextButton",fsCard)
fsNext.Size=UDim2.new(0,30,0,26); fsNext.Position=UDim2.new(1,-30,0.5,-13)
fsNext.BackgroundColor3=C.bg1; fsNext.Text="▶"; fsNext.TextColor3=C.yl1
fsNext.Font=Enum.Font.GothamBold; fsNext.TextSize=12; fsNext.ZIndex=7; cr(fsNext,6)
y4=y4+44
local fsEquip=Instance.new("TextButton",P4)
fsEquip.Size=UDim2.new(1,-12,0,30); fsEquip.Position=UDim2.new(0,6,0,y4)
fsEquip.BackgroundColor3=C.yl1; fsEquip.Text="✓  TERAPKAN STYLE"
fsEquip.TextColor3=Color3.fromRGB(10,10,10); fsEquip.Font=Enum.Font.GothamBlack
fsEquip.TextSize=11; fsEquip.ZIndex=5; cr(fsEquip,8)
y4=y4+36
fsPrev.MouseButton1Click:Connect(function()
    fi=fi-1; if fi<1 then fi=#FS end; fsLbl.Text="⚔ "..FS[fi]
end)
fsNext.MouseButton1Click:Connect(function()
    fi=fi+1; if fi>#FS then fi=1 end; fsLbl.Text="⚔ "..FS[fi]
end)
fsEquip.MouseButton1Click:Connect(function()
    local name=FS[fi]
    lp:SetAttribute("FightingStyle","")
    task.wait(0.15)
    lp:SetAttribute("FightingStyle",name)
    -- Play suara langsung dari SoundService
    local ss=game:GetService("SoundService")
    local folder=ss:FindFirstChild(name)
    if folder then
        local swing=folder:FindFirstChild("CustomSwingSound")
        if swing then swing:Play() end
    else
        -- Default: pakai Swing.Swing
        local def=ss:FindFirstChild("Swing")
        if def then
            local s=def:FindFirstChild("Swing")
            if s then s:Play() end
        end
    end
    fsEquip.Text="✓ "..name; task.delay(2,function() fsEquip.Text="✓  TERAPKAN STYLE" end)
end)
end

sec(P4,y4,"TEMA GUI",C.p2); y4=y4+23
do
local THEMES={
    {nm="🌆 Cyberpunk",   bg0={4,4,12},   bg1={7,7,18},    bg2={11,11,26},  border={30,30,55},   p1={140,50,240},  cy1={0,220,255},   glow={130,50,220}},
    {nm="🌸 Sakura",      bg0={12,4,8},   bg1={18,6,12},   bg2={26,10,18},  border={55,20,35},   p1={255,100,180}, cy1={255,160,210},  glow={255,80,160}},
    {nm="🩸 Blood Moon",  bg0={10,2,2},   bg1={18,3,3},    bg2={26,5,5},    border={55,10,10},   p1={220,30,30},   cy1={255,60,60},    glow={200,20,20}},
    {nm="💚 Military",    bg0={4,8,4},    bg1={6,12,6},    bg2={10,18,10},  border={20,40,20},   p1={60,180,60},   cy1={100,220,80},   glow={40,160,40}},
    {nm="🌌 Void",        bg0={4,2,12},   bg1={6,3,18},    bg2={10,5,26},   border={25,10,55},   p1={120,40,255},  cy1={160,80,255},   glow={100,20,240}},
    {nm="🔵 Hologram",    bg0={2,8,14},   bg1={3,12,20},   bg2={5,18,30},   border={10,40,70},   p1={0,180,255},   cy1={80,220,255},   glow={0,160,240}},
}
local ti=1
local thCard=Instance.new("Frame",P4)
thCard.Size=UDim2.new(1,-12,0,38); thCard.Position=UDim2.new(0,6,0,y4)
thCard.BackgroundColor3=C.bg0; thCard.ZIndex=5; cr(thCard,8); sk(thCard,C.p2,1.2,0.35)
local thLbl=tx(thCard,THEMES[ti].nm,12,C.p2,Enum.Font.GothamBlack,6)
thLbl.Size=UDim2.new(1,-70,1,0); thLbl.Position=UDim2.new(0,8,0,0)
thLbl.TextXAlignment=Enum.TextXAlignment.Left
local thPrev=Instance.new("TextButton",thCard)
thPrev.Size=UDim2.new(0,30,0,26); thPrev.Position=UDim2.new(1,-64,0.5,-13)
thPrev.BackgroundColor3=C.bg1; thPrev.Text="◀"; thPrev.TextColor3=C.p2
thPrev.Font=Enum.Font.GothamBold; thPrev.TextSize=12; thPrev.ZIndex=7; cr(thPrev,6)
local thNext=Instance.new("TextButton",thCard)
thNext.Size=UDim2.new(0,30,0,26); thNext.Position=UDim2.new(1,-30,0.5,-13)
thNext.BackgroundColor3=C.bg1; thNext.Text="▶"; thNext.TextColor3=C.p2
thNext.Font=Enum.Font.GothamBold; thNext.TextSize=12; thNext.ZIndex=7; cr(thNext,6)
y4=y4+44
local thApply=Instance.new("TextButton",P4)
thApply.Size=UDim2.new(1,-12,0,30); thApply.Position=UDim2.new(0,6,0,y4)
thApply.BackgroundColor3=C.p2; thApply.Text="🎨  TERAPKAN TEMA"
thApply.TextColor3=Color3.fromRGB(10,10,20); thApply.Font=Enum.Font.GothamBlack
thApply.TextSize=11; thApply.ZIndex=5; cr(thApply,8)
y4=y4+36

local function rgb(t) return Color3.fromRGB(t[1],t[2],t[3]) end
local function applyTheme(th)
    local b0=rgb(th.bg0); local b1=rgb(th.bg1); local b2=rgb(th.bg2)
    local bo=rgb(th.border); local pp=rgb(th.p1); local cy=rgb(th.cy1); local gl=rgb(th.glow)
    C.bg0=b0; C.bg1=b1; C.bg2=b2; C.border=bo; C.p1=pp; C.cy1=cy; C.glow=gl

    -- Update semua elemen di dalam Gui (termasuk luar Frame)
    for _,v in pairs(Gui:GetDescendants()) do
        pcall(function()
            if v:IsA("UIStroke") then
                local r,g,b2=v.Color.R*255,v.Color.G*255,v.Color.B*255
                if (r+g+b2)/3 < 80 then v.Color=bo end
            elseif v:IsA("Frame") or v:IsA("ScrollingFrame") or v:IsA("TextButton") or v:IsA("TextLabel") or v:IsA("ImageLabel") then
                if v.BackgroundTransparency < 0.95 then
                    local r,g,b2=v.BackgroundColor3.R*255,v.BackgroundColor3.G*255,v.BackgroundColor3.B*255
                    local br=(r+g+b2)/3
                    if br<20 then v.BackgroundColor3=b0
                    elseif br<35 then v.BackgroundColor3=b1
                    elseif br<60 then v.BackgroundColor3=b2 end
                end
            end
        end)
    end

    -- Force update elemen utama
    Frame.BackgroundColor3=b1
    Hdr.BackgroundColor3=b0
    TabBar.BackgroundColor3=b0
    Info.BackgroundColor3=b0
    PHolder.BackgroundColor3=b0
    for _,pg in pairs(pages) do pg.BackgroundColor3=b0 end
    pcall(function() Glow.ImageColor3=gl end)
    pcall(function() Glow2.ImageColor3=pp end)

    -- Update tombol luar (FlightBtn, FightingBtn, AutoGrabBtn, LockBtn)
    for _,v in pairs(Frame:GetChildren()) do
        pcall(function()
            if v:IsA("TextButton") and v.BackgroundTransparency < 0.95 then
                local r,g,b2=v.BackgroundColor3.R*255,v.BackgroundColor3.G*255,v.BackgroundColor3.B*255
                if (r+g+b2)/3 < 35 then v.BackgroundColor3=b1 end
            end
        end)
    end
end
thPrev.MouseButton1Click:Connect(function()
    ti=ti-1; if ti<1 then ti=#THEMES end; thLbl.Text=THEMES[ti].nm
end)
thNext.MouseButton1Click:Connect(function()
    ti=ti+1; if ti>#THEMES then ti=1 end; thLbl.Text=THEMES[ti].nm
end)
thApply.MouseButton1Click:Connect(function()
    applyTheme(THEMES[ti])
    thApply.Text="✓ Diterapkan!"; task.delay(2,function() thApply.Text="🎨  TERAPKAN TEMA" end)
end)
end

P4.CanvasSize=UDim2.new(0,0,0,y4+4)

-- Watermark
local WMark=tx(Frame,"fio · cyber · private",6,Color3.fromRGB(28,28,52),Enum.Font.Gotham,3)
WMark.Size=UDim2.new(1,0,0,10); WMark.Position=UDim2.new(0,0,1,-11)
WMark.TextXAlignment=Enum.TextXAlignment.Center; WMark.BackgroundTransparency=1

-- ═══════════════════════════════════════════════════════════════
--  AUTO GRAB BUTTON — kanan luar Frame, sejajar header
-- ═══════════════════════════════════════════════════════════════
local AutoGrabBtn = Instance.new("TextButton", Frame)
AutoGrabBtn.Size             = UDim2.new(0, 36, 0, 36)
AutoGrabBtn.Position         = UDim2.new(1, 4, 0, 0)   -- kanan Frame
AutoGrabBtn.BackgroundColor3 = C.bg1
AutoGrabBtn.Text             = "🤜"
AutoGrabBtn.TextColor3       = C.pk1
AutoGrabBtn.Font             = Enum.Font.GothamBlack
AutoGrabBtn.TextSize         = 16
AutoGrabBtn.AutoButtonColor  = false
AutoGrabBtn.ZIndex           = 10
AutoGrabBtn.Visible          = false
cr(AutoGrabBtn, 8)
local autogSK = sk(AutoGrabBtn, C.pk1, 1.2, 0.4)
local autogLbl = Instance.new("TextLabel", AutoGrabBtn)
autogLbl.Size=UDim2.new(1,0,0,10); autogLbl.Position=UDim2.new(0,0,1,-11)
autogLbl.BackgroundTransparency=1; autogLbl.Text="OFF"
autogLbl.TextColor3=Color3.fromRGB(160,80,160); autogLbl.Font=Enum.Font.GothamBold
autogLbl.TextSize=7; autogLbl.ZIndex=11

-- ═══════════════════════════════════════════════════════════════
--  LOCK GUI BUTTON — kiri Frame, di bawah FightingBtn
-- ═══════════════════════════════════════════════════════════════
local LockBtn = Instance.new("TextButton", Frame)
LockBtn.Size             = UDim2.new(0, 36, 0, 36)
LockBtn.Position         = UDim2.new(0, -(36+4), 0, 40)  -- kiri, bawah FightingBtn
LockBtn.BackgroundColor3 = C.bg1
LockBtn.Text             = "🔓"
LockBtn.TextColor3       = C.t1
LockBtn.Font             = Enum.Font.GothamBlack
LockBtn.TextSize         = 16
LockBtn.AutoButtonColor  = false
LockBtn.ZIndex           = 10
LockBtn.Visible          = false
cr(LockBtn, 8)
local lockSK = sk(LockBtn, C.border, 1.2, 0.5)
local lockLbl = Instance.new("TextLabel", LockBtn)
lockLbl.Size=UDim2.new(1,0,0,10); lockLbl.Position=UDim2.new(0,0,1,-11)
lockLbl.BackgroundTransparency=1; lockLbl.Text="OFF"
lockLbl.TextColor3=C.t0; lockLbl.Font=Enum.Font.GothamBold
lockLbl.TextSize=7; lockLbl.ZIndex=11
-- ═══════════════════════════════════════════════════════════════
local FlightBtn = Instance.new("TextButton", Frame)
FlightBtn.Size=UDim2.new(1,0,0,36); FlightBtn.Position=UDim2.new(0,0,1,0)
FlightBtn.BackgroundColor3=C.bg1; FlightBtn.Text="✈  FLIGHT  ·  OFF"
FlightBtn.TextColor3=C.yl1; FlightBtn.Font=Enum.Font.GothamBlack; FlightBtn.TextSize=12
FlightBtn.AutoButtonColor=false; FlightBtn.ZIndex=10; FlightBtn.ClipsDescendants=false; FlightBtn.Visible=false
cr(FlightBtn,8)
local flightSK=sk(FlightBtn,C.yl1,1.2,0.4);do local flightLine=Instance.new("Frame",FlightBtn); flightLine.Size=UDim2.new(1,0,0,2); flightLine.Position=UDim2.new(0,0,1,-2); flightLine.BackgroundColor3=C.yl1; flightLine.BackgroundTransparency=0.4; flightLine.ZIndex=11 end

local FightingBtn=Instance.new("TextButton",Frame)
FightingBtn.Size=UDim2.new(0,36,0,36); FightingBtn.Position=UDim2.new(0,-(36+4),0,0)
FightingBtn.BackgroundColor3=C.bg1; FightingBtn.Text="⚔"; FightingBtn.TextColor3=Color3.fromRGB(255,80,80)
FightingBtn.Font=Enum.Font.GothamBlack; FightingBtn.TextSize=16; FightingBtn.AutoButtonColor=false
FightingBtn.ZIndex=10; FightingBtn.Visible=false; cr(FightingBtn,8)
local fightingSK=sk(FightingBtn,Color3.fromRGB(255,80,80),1.2,0.4)
local fightingLbl=Instance.new("TextLabel",FightingBtn); fightingLbl.Size=UDim2.new(1,0,0,10); fightingLbl.Position=UDim2.new(0,0,1,-11); fightingLbl.BackgroundTransparency=1; fightingLbl.Text="OFF"; fightingLbl.TextColor3=Color3.fromRGB(160,80,80); fightingLbl.Font=Enum.Font.GothamBold; fightingLbl.TextSize=7; fightingLbl.ZIndex=11

-- ═══════════════════════════════════════════════════════════════
--  MINIMIZE + DRAG
-- ═══════════════════════════════════════════════════════════════
local minimized=false; local drag,dStart,dPos=false,nil,nil; local guiLocked=false

MinBtn.MouseButton1Click:Connect(function()
    minimized=not minimized
    PHolder.Visible=not minimized; Info.Visible=not minimized; TabBar.Visible=not minimized
    FlightBtn.Visible=minimized
    FightingBtn.Visible=minimized
    AutoGrabBtn.Visible=minimized
    LockBtn.Visible=minimized
    local nh=minimized and HDR_H or H
    TweenService:Create(Frame, TweenInfo.new(0.18,Enum.EasingStyle.Quad), {Size=UDim2.new(0,W,0,nh)}):Play()
    Glow.Size=UDim2.new(0,W+16,0,nh+16); Glow2.Size=UDim2.new(0,W+6,0,nh+6)
    MinBtn.Text=minimized and "＋" or "—"
end)
Hdr.InputBegan:Connect(function(i)
    if guiLocked then return end
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then
        drag=true; dStart=i.Position; dPos=Frame.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if not drag then return end
    if i.UserInputType==Enum.UserInputType.MouseMovement
    or i.UserInputType==Enum.UserInputType.Touch then
        local d=i.Position-dStart
        local np=UDim2.new(dPos.X.Scale,dPos.X.Offset+d.X,dPos.Y.Scale,dPos.Y.Offset+d.Y)
        Frame.Position=np
        Glow.Position=UDim2.new(np.X.Scale,np.X.Offset-8,np.Y.Scale,np.Y.Offset-8)
        Glow2.Position=UDim2.new(np.X.Scale,np.X.Offset-3,np.Y.Scale,np.Y.Offset-3)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then drag=false end
end)

-- ═══════════════════════════════════════════════════════════════
--  HITBOX HELPERS
-- ═══════════════════════════════════════════════════════════════
local function shrinkOwn()
    local c=lp.Character; if not c then return end
    local hrp=c:FindFirstChild("HumanoidRootPart")
    if hrp and not ownSize then
        ownSize=hrp.Size; ownTrans=hrp.Transparency
        local cf=hrp.CFrame
        hrp.Size=Vector3.new(3,3,3); hrp.CFrame=cf
        hrp.Transparency=1; hrp.LocalTransparencyModifier=1
    end
end
local function restoreOwn()
    local c=lp.Character
    if c and ownSize then
        local hrp=c:FindFirstChild("HumanoidRootPart")
        if hrp then
            local cf=hrp.CFrame; hrp.Size=ownSize; hrp.CFrame=cf
            hrp.Transparency=ownTrans or 0; hrp.LocalTransparencyModifier=0
        end
        ownSize=nil; ownTrans=nil
    end
end
local function applyHB(hrp)
    if not hrp or not hrp.Parent then return end
    if not origSizes[hrp] then
        origSizes[hrp]=hrp.Size; origTrans[hrp]=hrp.Transparency; origCC[hrp]=hrp.CanCollide
    end
    local cf=hrp.CFrame; hrp.CanCollide=false
    hrp.Size=Vector3.new(HitboxSize,HitboxSize,HitboxSize); hrp.CFrame=cf
    hrp.Transparency=1; hrp.LocalTransparencyModifier=1; expanded[hrp]=true
end
local function restoreHB(hrp)
    if origSizes[hrp] and hrp and hrp.Parent then
        local cf=hrp.CFrame; hrp.CanCollide=origCC[hrp] or false
        hrp.Size=origSizes[hrp]; hrp.CFrame=cf
        hrp.Transparency=origTrans[hrp] or 0; hrp.LocalTransparencyModifier=0
    end
    expanded[hrp]=nil; origSizes[hrp]=nil; origTrans[hrp]=nil; origCC[hrp]=nil
end

-- ═══════════════════════════════════════════════════════════════
--  PLAYER LIST
-- ═══════════════════════════════════════════════════════════════
local function refreshList()
    for _,c in ipairs(LScroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=lp then
            local b=Instance.new("TextButton",LScroll)
            b.Size=UDim2.new(1,0,0,26)
            local isTgt=(plr==currentTarget)
            b.BackgroundColor3=isTgt and C.gnDim or C.bg2
            b.Text=(isTgt and "» " or "  ")..plr.Name
            b.TextColor3=isTgt and C.gn1 or C.t1
            b.Font=Enum.Font.GothamSemibold; b.TextSize=11
            b.ZIndex=6; b.AutoButtonColor=false; cr(b,6)
            if isTgt then sk(b,C.gn0,1,0.45) end
            b.MouseButton1Click:Connect(function()
                currentTarget=(currentTarget==plr) and nil or plr
                StatLbl.Text=currentTarget and "  ◈  "..currentTarget.Name or "  Target: None"
                refreshList()
            end)
        end
    end
    LScroll.CanvasSize=UDim2.new(0,0,0,LLayout.AbsoluteContentSize.Y+6)
end
Players.PlayerAdded:Connect(refreshList)
Players.PlayerRemoving:Connect(refreshList)
refreshList()

-- ═══════════════════════════════════════════════════════════════
--  LOOPS
-- ═══════════════════════════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    local c=lp.Character; if not c then return end
    local h=c:FindFirstChild("Humanoid")
    if h then h.WalkSpeed=CurrentSpeed end
end)

RunService.RenderStepped:Connect(function()
    local c=lp.Character; if not c then return end
    local hum=c:FindFirstChild("Humanoid"); if not hum then return end
    if AntiRagdollEnabled then
        local st=hum:GetState()
        if st==Enum.HumanoidStateType.Physics
        or st==Enum.HumanoidStateType.Freefall
        or st==Enum.HumanoidStateType.Seated then
            hum:ChangeState(Enum.HumanoidStateType.Running); restoreJoints()
        end
    elseif AlwaysRagdollEnabled then
        if hum:GetState()~=Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  TOGGLE LOGIC
-- ═══════════════════════════════════════════════════════════════

-- Helpers
local function uiOffAlwaysRag()
    AlwaysRagdollEnabled=false; disableAlwaysRagdoll()
    AlwaysRagBtn.Text="💀  ALWAYS RAGDOLL  ·  OFF"; AlwaysRagBtn.TextColor3=C.pk2
    AlwaysRagBtn.BackgroundColor3=C.bg2; alwRagSK.Color=C.border; alwRagSK.Transparency=0.5
end
local function uiOffAntiRag()
    AntiRagdollEnabled=false
    ARBtn.Text="🦴  ANTI RAGDOLL  ·  OFF"; ARBtn.TextColor3=C.cy2
    ARBtn.BackgroundColor3=C.bg2; arSK.Color=C.border; arSK.Transparency=0.5
end

-- AURA
local function setAura(on)
    AuraEnabled=on
    if on then
        AuraBtn.Text="⚡  MANUAL AURA  ·  ON"; AuraBtn.TextColor3=C.cy2
        AuraBtn.BackgroundColor3=C.cyDim; auraSK.Color=C.cy1; auraSK.Transparency=0.15
        auraLine.BackgroundColor3=C.cy1; shrinkOwn()
    else
        AuraBtn.Text="⚡  MANUAL AURA  ·  OFF"; AuraBtn.TextColor3=C.cy1
        AuraBtn.BackgroundColor3=C.bg0; auraSK.Color=C.cy1; auraSK.Transparency=0.35
        auraLine.BackgroundColor3=C.cy1
        for h in pairs(expanded) do restoreHB(h) end
        restoreOwn(); currentTarget=nil
        OrbitEnabled=false
        OrbitBtn.Text="🔄  ORBIT LOCK  ·  OFF"; OrbitBtn.TextColor3=C.cy1
        OrbitBtn.BackgroundColor3=C.bg2; orbitSK.Color=C.border; orbitSK.Transparency=0.5
        FloatEnabled=false
        FloatBtn.Text="🕊  FLOAT ABOVE  ·  OFF"; FloatBtn.TextColor3=C.p2
        FloatBtn.BackgroundColor3=C.bg2; floatSK.Color=C.border; floatSK.Transparency=0.5
        StatLbl.Text="  Target: None"; refreshList()
    end
end
AuraBtn.Activated:Connect(function() setAura(not AuraEnabled) end)

AutoBtn.Activated:Connect(function()
    AutoTargetEnabled=not AutoTargetEnabled
    if AutoTargetEnabled then
        AutoBtn.Text="🎯  AUTO TARGET  ·  ON"; AutoBtn.TextColor3=C.gn1
        AutoBtn.BackgroundColor3=C.gnDim; autoSK.Color=C.gn1; autoSK.Transparency=0.45
    else
        AutoBtn.Text="🎯  AUTO TARGET  ·  OFF"; AutoBtn.TextColor3=C.t1
        AutoBtn.BackgroundColor3=C.bg2; autoSK.Color=C.border; autoSK.Transparency=0.5
    end
end)

OrbitBtn.Activated:Connect(function()
    if not AuraEnabled then StatLbl.Text="  ⚠ Nyalain AURA dulu!"; return end
    OrbitEnabled=not OrbitEnabled
    if OrbitEnabled then
        OrbitBtn.Text="🔄  ORBIT LOCK  ·  ON"; OrbitBtn.TextColor3=C.cy2
        OrbitBtn.BackgroundColor3=C.cyDim; orbitSK.Color=C.cy1; orbitSK.Transparency=0.35; orbitAngle=0
        FloatEnabled=false
        FloatBtn.Text="🕊  FLOAT ABOVE  ·  OFF"; FloatBtn.TextColor3=C.p2
        FloatBtn.BackgroundColor3=C.bg2; floatSK.Color=C.border; floatSK.Transparency=0.5
    else
        OrbitBtn.Text="🔄  ORBIT LOCK  ·  OFF"; OrbitBtn.TextColor3=C.cy1
        OrbitBtn.BackgroundColor3=C.bg2; orbitSK.Color=C.border; orbitSK.Transparency=0.5
    end
end)

FloatBtn.Activated:Connect(function()
    if not AuraEnabled then StatLbl.Text="  ⚠ Nyalain AURA dulu!"; return end
    FloatEnabled=not FloatEnabled
    if FloatEnabled then
        FloatBtn.Text="🕊  FLOAT ABOVE  ·  ON"; FloatBtn.TextColor3=C.p2
        FloatBtn.BackgroundColor3=C.pDim; floatSK.Color=C.p1; floatSK.Transparency=0.35
        OrbitEnabled=false
        OrbitBtn.Text="🔄  ORBIT LOCK  ·  OFF"; OrbitBtn.TextColor3=C.cy1
        OrbitBtn.BackgroundColor3=C.bg2; orbitSK.Color=C.border; orbitSK.Transparency=0.5
    else
        FloatBtn.Text="🕊  FLOAT ABOVE  ·  OFF"; FloatBtn.TextColor3=C.p2
        FloatBtn.BackgroundColor3=C.bg2; floatSK.Color=C.border; floatSK.Transparency=0.5
    end
end)

ARBtn.Activated:Connect(function()
    AntiRagdollEnabled=not AntiRagdollEnabled
    if AntiRagdollEnabled then
        if AlwaysRagdollEnabled then uiOffAlwaysRag() end
        ARBtn.Text="🦴  ANTI RAGDOLL  ·  ON"; ARBtn.TextColor3=C.cy2
        ARBtn.BackgroundColor3=C.cyDim; arSK.Color=C.cy1; arSK.Transparency=0.35
    else
        ARBtn.Text="🦴  ANTI RAGDOLL  ·  OFF"; ARBtn.TextColor3=C.cy2
        ARBtn.BackgroundColor3=C.bg2; arSK.Color=C.border; arSK.Transparency=0.5
    end
end)

AlwaysRagBtn.Activated:Connect(function()
    AlwaysRagdollEnabled=not AlwaysRagdollEnabled
    if AlwaysRagdollEnabled then
        if AntiRagdollEnabled then uiOffAntiRag() end
        AlwaysRagBtn.Text="💀  ALWAYS RAGDOLL  ·  ON"; AlwaysRagBtn.TextColor3=C.pk2
        AlwaysRagBtn.BackgroundColor3=C.pkDim; alwRagSK.Color=C.pk1; alwRagSK.Transparency=0.35
        enableAlwaysRagdoll()
    else
        AlwaysRagBtn.Text="💀  ALWAYS RAGDOLL  ·  OFF"; AlwaysRagBtn.TextColor3=C.pk2
        AlwaysRagBtn.BackgroundColor3=C.bg2; alwRagSK.Color=C.border; alwRagSK.Transparency=0.5
        disableAlwaysRagdoll()
    end
end)

AntiAuraBtn.Activated:Connect(function()
    AntiAuraEnabled=not AntiAuraEnabled
    if AntiAuraEnabled then
        AntiAuraBtn.Text="🌀  ANTI AURA  ·  ON"; AntiAuraBtn.TextColor3=C.or1
        AntiAuraBtn.BackgroundColor3=C.orDim; antiAuraSK.Color=C.or1; antiAuraSK.Transparency=0.35
        enableAntiAura()
    else
        AntiAuraBtn.Text="🌀  ANTI AURA  ·  OFF"; AntiAuraBtn.TextColor3=C.or1
        AntiAuraBtn.BackgroundColor3=C.bg2; antiAuraSK.Color=C.border; antiAuraSK.Transparency=0.5
        disableAntiAura()
    end
end)

FlightBtn.Activated:Connect(function()
    FlightEnabled=not FlightEnabled
    if FlightEnabled then
        FlightBtn.Text="✈  FLIGHT  ·  ON"; FlightBtn.TextColor3=C.yl1
        FlightBtn.BackgroundColor3=C.ylDim; flightSK.Color=C.yl1; flightSK.Transparency=0.2
        loadFlightAnims(); startFlight()
    else
        FlightBtn.Text="✈  FLIGHT  ·  OFF"; FlightBtn.TextColor3=C.yl1
        FlightBtn.BackgroundColor3=C.bg1; flightSK.Color=C.yl1; flightSK.Transparency=0.4
        stopFlight()
    end
end)

-- AUTO GRAB TOGGLE
AutoGrabBtn.Activated:Connect(function()
    AutoGrabEnabled=not AutoGrabEnabled
    if AutoGrabEnabled then
        AutoGrabBtn.BackgroundColor3=C.pkDim; autogSK.Color=C.pk1; autogSK.Transparency=0.2
        autogLbl.Text="ON"; autogLbl.TextColor3=C.pk1
        startGrabLoop()
    else
        AutoGrabBtn.BackgroundColor3=C.bg1; autogSK.Color=C.pk1; autogSK.Transparency=0.4
        autogLbl.Text="OFF"; autogLbl.TextColor3=Color3.fromRGB(160,80,160)
        stopGrabLoopIfIdle()
    end
end)

-- LOCK GUI TOGGLE
LockBtn.Activated:Connect(function()
    guiLocked=not guiLocked
    if guiLocked then
        LockBtn.Text="🔒"; lockSK.Color=C.yl1; lockSK.Transparency=0.3
        LockBtn.BackgroundColor3=C.ylDim
        lockLbl.Text="ON"; lockLbl.TextColor3=C.yl1
    else
        LockBtn.Text="🔓"; lockSK.Color=C.border; lockSK.Transparency=0.5
        LockBtn.BackgroundColor3=C.bg1
        lockLbl.Text="OFF"; lockLbl.TextColor3=C.t0
    end
end)

-- FIGHTING TOGGLE
local fightingOn = false
FightingBtn.Activated:Connect(function()
    fightingOn = not fightingOn
    lp:SetAttribute("Fighting", fightingOn)
    if fightingOn then
        FightingBtn.BackgroundColor3 = Color3.fromRGB(80,10,10)
        fightingSK.Color             = Color3.fromRGB(255,80,80)
        fightingSK.Transparency      = 0.2
        fightingLbl.Text             = "ON"
        fightingLbl.TextColor3       = Color3.fromRGB(255,100,100)
    else
        FightingBtn.BackgroundColor3 = C.bg1
        fightingSK.Color             = Color3.fromRGB(255,80,80)
        fightingSK.Transparency      = 0.4
        fightingLbl.Text             = "OFF"
        fightingLbl.TextColor3       = Color3.fromRGB(160,80,80)
    end
end)
-- Sync visual kalau Fighting berubah dari game
lp:GetAttributeChangedSignal("Fighting"):Connect(function()
    fightingOn = lp:GetAttribute("Fighting") == true
    if fightingOn then
        FightingBtn.BackgroundColor3=Color3.fromRGB(80,10,10)
        fightingSK.Transparency=0.2; fightingLbl.Text="ON"
        fightingLbl.TextColor3=Color3.fromRGB(255,100,100)
    else
        FightingBtn.BackgroundColor3=C.bg1
        fightingSK.Transparency=0.4; fightingLbl.Text="OFF"
        fightingLbl.TextColor3=Color3.fromRGB(160,80,80)
    end
end)

-- ATTACK SPEED toggle
AtkSpeedBtn.Activated:Connect(function()
    AtkSpeedEnabled = not AtkSpeedEnabled
    if AtkSpeedEnabled then
        AtkSpeedBtn.Text="🥊  FIO AURA MODE  ·  ON"; AtkSpeedBtn.TextColor3=C.or1
        AtkSpeedBtn.BackgroundColor3=C.orDim; atkSpeedSK.Color=C.or1; atkSpeedSK.Transparency=0.2
        atkLine.BackgroundColor3=C.or1; atkLine.BackgroundTransparency=0.2
        atkStatLbl.Text="  ⚡ L1+L2+L3 aktif — coba serang"; atkStatLbl.TextColor3=C.gn1
        enableAtkSpeed()
    else
        AtkSpeedBtn.Text="🥊  FIO AURA MODE  ·  OFF"; AtkSpeedBtn.TextColor3=C.or1
        AtkSpeedBtn.BackgroundColor3=C.bg0; atkSpeedSK.Color=C.or1; atkSpeedSK.Transparency=0.4
        atkLine.BackgroundColor3=C.or1; atkLine.BackgroundTransparency=0.4
        atkStatLbl.Text="  Remote: none detected"; atkStatLbl.TextColor3=C.t1
        disableAtkSpeed()
    end
end)

-- Numeric control untuk AtkSpeedMult
atkM.MouseButton1Click:Connect(function()
    AtkSpeedMult=math.max(AtkSpdMin, AtkSpeedMult-1)
    atkV.Text=tostring(AtkSpeedMult)
end)
atkP.MouseButton1Click:Connect(function()
    AtkSpeedMult=math.min(AtkSpdMax, AtkSpeedMult+1)
    atkV.Text=tostring(AtkSpeedMult)
end)

-- Update status label sudah inline di _autoSelectCapture dan _startReplayLoop

spdM.MouseButton1Click:Connect(function() CurrentSpeed=math.max(SpeedMin,CurrentSpeed-5);spdV.Text=tostring(CurrentSpeed) end)
spdP.MouseButton1Click:Connect(function() CurrentSpeed=math.min(SpeedMax,CurrentSpeed+5);spdV.Text=tostring(CurrentSpeed) end)
fltM.MouseButton1Click:Connect(function() FloatHeight=math.max(1,FloatHeight-1);fltV.Text=tostring(FloatHeight) end)
fltP.MouseButton1Click:Connect(function() FloatHeight=math.min(50,FloatHeight+1);fltV.Text=tostring(FloatHeight) end)
hbM.MouseButton1Click:Connect(function() HitboxSize=math.max(10,HitboxSize-5);hbV.Text=tostring(HitboxSize) end)
hbP.MouseButton1Click:Connect(function() HitboxSize=math.min(200,HitboxSize+5);hbV.Text=tostring(HitboxSize) end)
rnM.MouseButton1Click:Connect(function() Range=math.max(5,Range-5);rnV.Text=tostring(Range) end)
rnP.MouseButton1Click:Connect(function() Range=math.min(150,Range+5);rnV.Text=tostring(Range) end)
orRM.MouseButton1Click:Connect(function() orbitRadius=math.max(2,orbitRadius-1);orRV.Text=tostring(orbitRadius) end)
orRP.MouseButton1Click:Connect(function() orbitRadius=math.min(30,orbitRadius+1);orRV.Text=tostring(orbitRadius) end)
orSM.MouseButton1Click:Connect(function() orbitSpeed=math.max(1,orbitSpeed-1);orSV.Text=tostring(orbitSpeed) end)
orSP.MouseButton1Click:Connect(function() orbitSpeed=math.min(30,orbitSpeed+1);orSV.Text=tostring(orbitSpeed) end)
RstBtn.MouseButton1Click:Connect(function() CurrentSpeed=25;spdV.Text="25" end)


-- ═══════════════════════════════════════════════════════════════
--  MAIN HEARTBEAT LOOP
-- ═══════════════════════════════════════════════════════════════
RunService.Heartbeat:Connect(function(dt)
    if not AuraEnabled then return end
    local char=lp.Character; if not char then return end
    local root=char:FindFirstChild("HumanoidRootPart")
    local hum=char:FindFirstChild("Humanoid")
    if not root or not hum then return end

    if AutoTargetEnabled and not currentTarget then
        local best,bestD=nil,math.huge
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr~=lp and plr.Character then
                local hrp=plr.Character:FindFirstChild("HumanoidRootPart")
                local h=plr.Character:FindFirstChild("Humanoid")
                if hrp and h and h.Health>0 then
                    local d=(root.Position-hrp.Position).Magnitude
                    if d<=Range and d<bestD then bestD=d;best=plr end
                end
            end
        end
        if best~=currentTarget then currentTarget=best; if currentTarget then refreshList() end end
    end

    if currentTarget then
        local tChar=currentTarget.Character
        if not tChar then currentTarget=nil;StatLbl.Text="  Target: None";refreshList();return end
        local tHRP=tChar:FindFirstChild("HumanoidRootPart")
        local tHum=tChar:FindFirstChild("Humanoid")
        if tHRP and tHum and tHum.Health>0 then
            applyHB(tHRP)
            if OrbitEnabled then
                orbitAngle=orbitAngle+orbitSpeed*dt
                local tp=tHRP.Position
                root.CFrame=CFrame.new(Vector3.new(tp.X+math.cos(orbitAngle)*orbitRadius,tp.Y,tp.Z+math.sin(orbitAngle)*orbitRadius),tp)
            elseif FloatEnabled then
                local tp=tHRP.Position
                root.CFrame=CFrame.new(Vector3.new(tp.X,tp.Y+FloatHeight+3,tp.Z),Vector3.new(tp.X,tp.Y,tp.Z))
            end
            local dist=(root.Position-tHRP.Position).Magnitude
            local tag=OrbitEnabled and " 🔄" or (FloatEnabled and " 🕊" or "")
            StatLbl.Text="  ◈  "..currentTarget.Name.."  ["..math.floor(dist).."s]"..tag
        else
            currentTarget=nil;StatLbl.Text="  Target: None";refreshList()
        end
    end

    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=lp and plr~=currentTarget and plr.Character then
            local hrp=plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then restoreHB(hrp) end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  RESPAWN HANDLER
-- ═══════════════════════════════════════════════════════════════
lp.CharacterAdded:Connect(function(char)
    task.wait(0.8)
    ownSize=nil; ownTrans=nil
    saveJoints(char); updateHp()
    if AuraEnabled          then shrinkOwn() end
    if AlwaysRagdollEnabled then task.wait(0.2); enableAlwaysRagdoll() end
    if FlightEnabled then
        stopFlight()
        task.wait(0.5); loadFlightAnims(); startFlight()
    end
    if AutoBlockEnabled then
        task.wait(0.3); enableAutoBlock()
    end
    if NoGrabCool or AutoGrabEnabled then
        task.wait(0.3); startGrabLoop()
    end
end)

print("✅ FIO AURA v7.0 [CYBERPUNK] — Aura|Float|Orbit|Ragdoll|Flight|FioAuraMode | Loaded!")

-- forceStopFly compat (beberapa game punya remote ini)
pcall(function()
    game.ReplicatedStorage.Remotes.forceStopFly.OnClientEvent:Connect(function()
        if FlightEnabled then
            FlightEnabled=false
            FlightBtn.Text="✈  FLIGHT  ·  OFF"; FlightBtn.TextColor3=C.yl1
            FlightBtn.BackgroundColor3=C.bg1; flightSK.Color=C.yl1; flightSK.Transparency=0.4
            stopFlight()
        end
    end)
end)
