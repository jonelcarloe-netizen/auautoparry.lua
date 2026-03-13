local OPCODE={LOADK=0,LOADBOOL=1,LOADNIL=2,MOVE=3,GETGLOBAL=4,SETGLOBAL=5,GETTABLE=6,SETTABLE=7,NEWTABLE=8,CALL=9,RETURN=10,JMP=11,EQ=12,LT=13,LE=14,TEST=15,TESTSET=16,ADD=17,SUB=18,MUL=19,DIV=20,MOD=21,POW=22,UNM=23,NOT=24,LEN=25,CONCAT=26,CLOSURE=27,FORPREP=28,FORLOOP=29,TFORLOOP=30,SETLIST=31,VARARG=32,GETUPVAL=33,SETUPVAL=34,SELF=35,DECODE=255}
local XOR_KEY=0x5A
local function vmEncode(s)
    local out={}
    for i=1,#s do
        local b=string.byte(s,i)
        local k=(XOR_KEY+(i-1))%256
        out[i]=bit32.bxor(b,k)
    end
    return out
end
local function vmDecode(t)
    local chars={}
    for i,v in ipairs(t) do
        local k=(XOR_KEY+(i-1))%256
        chars[i]=string.char(bit32.bxor(v,k))
    end
    return table.concat(chars)
end
local PAYLOAD_SOURCE=[[
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local VirtualInputManager=cloneref and cloneref(game:GetService("VirtualInputManager")) or game:GetService("VirtualInputManager")
local LocalPlayer=Players.LocalPlayer
local Character=LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local CONFIG={Enabled=true,ToggleKey=Enum.KeyCode.RightShift,ParryDelay=0.05,ParryCooldown=0.65,DetectionRadius=12,CheckInterval=0.05,Debug=false}
local lastParryTime=0
local lastCheckTime=0
local parryLocked=false
local function log(m) if CONFIG.Debug then print("[VM|AutoParry] "..tostring(m)) end end
local function getHRP(c) return c and c:FindFirstChild("HumanoidRootPart") end
local function isAlive(c) local h=c and c:FindFirstChildOfClass("Humanoid") return h and h.Health>0 end
local function pressParry()
    if parryLocked then return end
    local now=tick()
    if now-lastParryTime<CONFIG.ParryCooldown then return end
    parryLocked=true lastParryTime=now
    task.delay(CONFIG.ParryDelay,function()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.F,false,game)
        task.wait(0.08)
        VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.F,false,game)
        task.wait(0.05) parryLocked=false
    end)
end
local function hookRemotes()
    local names={"damageevent","hitevent","attackevent","takedamage","hit","damage","attack","strikeevent","blockbreak","combohit"}
    local function tryHook(r)
        if not r or not r:IsA("RemoteEvent") then return end
        local n=r.Name:lower()
        for _,t in ipairs(names) do
            if n:find(t,1,true) then
                r.OnClientEvent:Connect(function() if CONFIG.Enabled then pressParry() end end)
                break
            end
        end
    end
    local function scan(folder)
        for _,o in ipairs(folder:GetDescendants()) do tryHook(o) end
        folder.DescendantAdded:Connect(function(o) task.wait(0.1);tryHook(o) end)
    end
    scan(ReplicatedStorage)
    local wr=workspace:FindFirstChild("Remotes") or workspace:FindFirstChild("Events")
    if wr then scan(wr) end
end
local function proximityCheck()
    if not CONFIG.Enabled then return end
    local now=tick()
    if now-lastCheckTime<CONFIG.CheckInterval then return end
    lastCheckTime=now
    Character=LocalPlayer.Character
    if not Character or not isAlive(Character) then return end
    local myHRP=getHRP(Character)
    if not myHRP then return end
    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local c=p.Character
        if not c or not isAlive(c) then continue end
        local hrp=getHRP(c)
        if not hrp then continue end
        if (myHRP.Position-hrp.Position).Magnitude<=CONFIG.DetectionRadius then
            local anim=c:FindFirstChildOfClass("Animator") or (c:FindFirstChildOfClass("Humanoid") and c:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator"))
            if anim then
                for _,t in ipairs(anim:GetPlayingAnimationTracks()) do
                    local an=(t.Animation and t.Animation.Name or ""):lower()
                    if an:find("attack") or an:find("swing") or an:find("strike") or an:find("hit") or an:find("slash") or an:find("combo") then
                        pressParry() break
                    end
                end
            end
        end
    end
end
local function showNotif(enabled)
    local pg=LocalPlayer.PlayerGui
    local old=pg:FindFirstChild("__APNotif") if old then old:Destroy() end
    local g=Instance.new("ScreenGui",pg) g.Name="__APNotif" g.ResetOnSpawn=false
    local f=Instance.new("Frame",g)
    f.Size=UDim2.new(0,270,0,42) f.Position=UDim2.new(0.5,-135,0,18)
    f.BackgroundColor3=enabled and Color3.fromRGB(24,195,75) or Color3.fromRGB(195,45,45) f.BorderSizePixel=0
    local c2=Instance.new("UICorner",f) c2.CornerRadius=UDim.new(0,9)
    local l=Instance.new("TextLabel",f)
    l.Size=UDim2.new(1,0,1,0) l.BackgroundTransparency=1
    l.Text="Auto Parry [VM]: "..(enabled and "ON" or "OFF")
    l.TextColor3=Color3.fromRGB(255,255,255) l.TextScaled=true l.Font=Enum.Font.GothamBold
    task.delay(2.2,function() if g and g.Parent then g:Destroy() end end)
end
UserInputService.InputBegan:Connect(function(i,gp)
    if gp then return end
    if i.KeyCode==CONFIG.ToggleKey then CONFIG.Enabled=not CONFIG.Enabled showNotif(CONFIG.Enabled) end
end)
hookRemotes()
RunService.Heartbeat:Connect(proximityCheck)
LocalPlayer.CharacterAdded:Connect(function(c) Character=c end)
showNotif(true)
]]
local ENCODED=vmEncode(PAYLOAD_SOURCE)
local PROTO={
    K={[0]="LuaVM",[1]="AutoParry",[2]=0.05,[3]=true,[4]="__vm_env"},
    maxReg=8,
    code={{8,0,0,0},{0,1,0,0},{0,2,1,0},{7,0,2,2},{1,3,1,0},{7,0,3,3},{0,4,2,0},{7,0,4,4},{255,0,0,0},{10,0,1,0}}
}
local function vmExec(proto,upvalues,...)
    local R={} local K=proto.K local code=proto.code local pc=1 local args={...}
    for i,v in ipairs(args) do R[i-1]=v end
    local function RK(x) if x>=256 then return K[x-256] end return R[x] end
    while pc<=#code do
        local instr=code[pc] local op=instr[1] local A,B,C=instr[2],instr[3],instr[4]
        if op==0 then R[A]=K[B]
        elseif op==1 then R[A]=(B~=0) if C~=0 then pc=pc+1 end
        elseif op==2 then for i=A,A+B do R[i]=nil end
        elseif op==3 then R[A]=R[B]
        elseif op==4 then R[A]=_G[K[B]]
        elseif op==5 then _G[K[B]]=R[A]
        elseif op==6 then R[A]=R[B][RK(C)]
        elseif op==7 then R[A][RK(B)]=RK(C)
        elseif op==8 then R[A]={}
        elseif op==9 then
            local fn=R[A] local fnArgs={} for i=A+1,A+B-1 do fnArgs[#fnArgs+1]=R[i] end
            local results=table.pack(fn(table.unpack(fnArgs)))
            for i=1,C-1 do R[A+i-1]=results[i] end
        elseif op==10 then
            if B==1 then return end
            local rets={} for i=A,A+B-2 do rets[#rets+1]=R[i] end return table.unpack(rets)
        elseif op==17 then R[A]=RK(B)+RK(C)
        elseif op==18 then R[A]=RK(B)-RK(C)
        elseif op==24 then R[A]=not R[B]
        elseif op==255 then
            local src=vmDecode(ENCODED)
            local chunk,err=loadstring(src)
            if chunk then local ok,e=pcall(chunk) if not ok then warn("[LuaVM] "..tostring(e)) end
            else warn("[LuaVM] err: "..tostring(err)) end
            return
        end
        pc=pc+1
    end
end
task.spawn(function() vmExec(PROTO,nil) end)
