if not game:IsLoaded() then
	game.Loaded:Wait()
end
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Modules = {
	Common = require(Shared:WaitForChild("Common")),
	Collision = require(script:WaitForChild("Collision")),
	Velocity = require(script:WaitForChild("Velocity"))
}
_G.__phys_modules__ = setmetatable(Modules, {
	__index = function(self,i)
		local fenv = getfenv(2)
		if fenv.script and fenv.script:IsDescendantOf(script) then
			return rawget(self,i)
		end
	end,
	__metatable = nil
})
Modules.Instances = require(script:WaitForChild("Instances"))
Modules.tickHz = require(script:WaitForChild("tickHz"))

local S = Modules.Common.S
local thread = Modules.Common.thread
local Critical_wait = Modules.Common.Critical_wait
local New = Modules.Common.New
local PhysicsFPS = Modules.Common.PhysicsFPS
local PlayerFPS = Modules.Common.PlayerFPS

local Mover = Modules.Instances.Mover
local FC = Modules.Instances.FC
local Pointer = Modules.Instances.Pointer
local debug_lookX = Modules.Instances.debug_lookX
local debug_lookY = Modules.Instances.debug_lookY
local debug_lookZ = Modules.Instances.debug_lookZ

local Players = S.Players
local UIS = S.UserInputService

local V3, CN, ANG, lookAt = Vector3.new, CFrame.new, CFrame.Angles, CFrame.lookAt
local pi, clamp, abs, cos, sin, floor = math.pi, math.clamp, math.abs, math.cos, math.sin, math.floor

local PhysicsFPS_Remote = PhysicsFPS()
local PlayerFPS_Remote = PlayerFPS()

--Remove the default character
local cc = workspace.CurrentCamera
local function set_CameraPOV(BasePart)
	cc.CameraSubject = BasePart
	cc.CameraType = Enum.CameraType.Custom
end
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
char:Destroy()
set_CameraPOV(Mover)
FC.Parent = cc

--Init the workspace physics
--Critical dependency
local PhysicsList_Remote = Critical_wait(Shared, 'PhysicsList', 10, "Fetching PhysicsList Remote...", "Got the PhysicsList Remote.", "Failed to fetch the PhysicsList, The physics engine will not work!")
--
local PhysicsList = {}
local HitColliders = {
	x={},y={},z={},
	inv_x={},inv_y={},inv_z={}
}
local function Visual_HitCollisions(Type, Obj, Color, Side, Ang)
	HitColliders[Type][Obj] = New('Part', workspace, {
		Name='physics hit',
		Anchored=true,
		Size=V3(2,.1,2),
		Color=Color,
		Transparency=.5,
		Position=Obj.CFrame*Side,
		CFrame=Ang or CN()
	})
end
local function HitCollisions_Visibility(value)
	local tobool = value and .5 or 1
	for _,v in next, HitColliders.x do
		v.Transparency = tobool
	end
	for _,v in next, HitColliders.y do
		v.Transparency = tobool
	end
	for _,v in next, HitColliders.z do
		v.Transparency = tobool
	end
	for _,v in next, HitColliders.inv_x do
		v.Transparency = tobool
	end
	for _,v in next, HitColliders.inv_y do
		v.Transparency = tobool
	end
	for _,v in next, HitColliders.inv_z do
		v.Transparency = tobool
	end
end

--Controls
local Hold, Down, Up = {}, {}, {}
local MouseHit_p = Vector3.zero
local Freecam = false
local Ground = false
local OnGround = false
local Hit_Indicators = true

local function Reset()
	Mover.Position=Vector3.yAxis*300
end

function Down.f()
	Freecam = not Freecam
	if Freecam then
		set_CameraPOV(FC)
	else
		set_CameraPOV(Mover)
	end
	print("freecam=",Freecam)
end
function Down.r()
	Ground = not Ground
	Mover.Orientation=Vector3.zero
	print("Ground=",Ground)
end
function Down.t()
	print(PhysicsList)
	warn("Printed the PhysicsList.")
end
function Down.g()
	Hit_Indicators = not Hit_Indicators
	HitCollisions_Visibility(Hit_Indicators)
	print("hit indicators=",Hit_Indicators)
end

Down.y = Reset

UIS.InputBegan:Connect(function(input, gp)
	if not gp then
		local i = input.KeyCode.Name:lower()
		Hold[i] = true
		if Down[i] then
			Down[i]()
		end
	end
end)
UIS.InputEnded:Connect(function(input, gp)
	if not gp then
		local i = input.KeyCode.Name:lower()
		Hold[i] = false
		if Up[i] then
			Up[i]()
		end
	end
end)
UIS.InputChanged:Connect(function(input, _)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		MouseHit_p = input.Position
	end
end)

--Step info
--https://devforum-uploads.s3.dualstack.us-east-2.amazonaws.com/uploads/original/4X/0/b/6/0b6fde38a15dd528063a92ac8916ce3cd84fc1ce.png
local Heartbeat = Modules.tickHz.new(0, "Heartbeat")
local Stepped = Modules.tickHz.new(60, "Stepped")

local z = Vector3.zAxis/10
local ys = 1
local JumpHeight = 20
local Jumping = false

--Never recommend below 1 or else the hit detection will/can be to ~perfect~
local StudSteps = 1
local MaxGround_Detect = 100

local Fall_velocity = 1e-3
local Fall_velocity_level = 0
local Fall_velocity_max = 5

local function m_2D_3DVector() --This is NOT suppose to be mouse.Target or react's to physics *yet* -09/04
	local SPTR = cc:ScreenPointToRay(MouseHit_p.x,MouseHit_p.y,0)
	return (SPTR.Origin+Mover.CFrame.LookVector+SPTR.Direction*(cc.CFrame.p-Mover.CFrame.p).Magnitude*2)
end

local function ComputeJump()
	local goal = V3(0,JumpHeight/10,0)
	for i = 1, 10 do
		Stepped.TickStep:Wait()
		Mover.Position=Mover.Position:Lerp(Mover.Position+goal,i/10)
	end
	for i = 1, 10 do
		Mover.Position=Mover.Position:Lerp(Mover.Position-goal,i/10)
		Stepped.TickStep:Wait()
	end
end

Stepped.TickStep:Connect(function(tdt,dt)
	local lv, m_lv = cc.CFrame.LookVector, Mover.CFrame.LookVector
	local rv, m_rv = cc.CFrame.RightVector, Mover.CFrame.RightVector
	if Hold.w then
		if not Freecam then
			if Ground then
				Mover.Position+=m_lv+z
			else
				Mover.Position+=lv+z
			end
		else
			FC.Position+=lv+z
		end
	end
	if Hold.s then
		if not Freecam then
			if Ground then
				Mover.Position-=m_lv+z
			else
				Mover.Position-=lv+z
			end
		else
			FC.Position-=lv+z
		end
	end
	if Hold.a then
		if not Freecam then
			if Ground then
				Mover.Position-=m_rv+z
			else
				Mover.Position-=rv+z
			end
		else
			FC.Position-=rv+z
		end
	end
	if Hold.d then
		if not Freecam then
			if Ground then
				Mover.Position+=m_rv+z
			else
				Mover.Position+=rv+z
			end
		else
			FC.Position+=rv+z
		end
	end
	if Hold.e then
		if not Ground then
			if not Freecam then
				Mover.Position+=V3(0,ys,0)
			else
				FC.Position+=V3(0,ys,0)
			end
		end
	end
	if Hold.q then
		if not Ground then
			if not Freecam then
				Mover.Position-=V3(0,ys,0)
			else
				FC.Position-=V3(0,ys,0)
			end
		end
	end
	if Hold.space then
		if Ground and OnGround and not Jumping then
			Jumping = true
			ComputeJump()
			Jumping = false
		end
	end

	local Dir = m_2D_3DVector()
	local Mover_cf = Mover.CFrame
	if not Freecam then
		Pointer.Position=Mover_cf.p
		FC.Position=Mover.Position
		if not Ground then
			Mover.CFrame=lookAt(Mover.Position,Mover_cf.p)
		end
	end
	if Ground then
		debug_lookX.Transparency = 0
		debug_lookY.Transparency = 0
		debug_lookZ.Transparency = 0



		debug_lookX.CFrame=CN(Mover_cf.LookVector)*Mover_cf*ANG(pi/2,0,0)
		debug_lookY.CFrame=CN(Mover_cf.LookVector)*Mover_cf*ANG(0,pi/2,0)
		debug_lookZ.CFrame=CN(Mover_cf.LookVector)*Mover_cf*ANG(0,0,pi/2)
	else
		debug_lookX.Transparency = 1
		debug_lookY.Transparency = 1
		debug_lookZ.Transparency = 1
	end

	PlayerFPS_Remote:Fire(dt)
end)

local function ComputeFall_velocity(Object, Mover_p, y_hit_level)
	if Ground and not Jumping then
		local Ground_Detect = (y_hit_level+Mover_p).Unit+(Object.Size/2)
		local Ground_Unit = -((Ground_Detect-Mover_p).Unit.y*(Ground_Detect+Mover_p).Magnitude)
		if Ground_Unit>=StudSteps then
			OnGround = false
			Mover.Position-=V3(0,.1+Fall_velocity_level,0)
			Fall_velocity_level+=Fall_velocity
		else
			OnGround = true
			Fall_velocity_level=0
		end
	end
end

local function ComputePhysics(Object, Mover_p)
	local Collision_data = Modules.Collision.new_block(Object, Mover)
	local Sides = Collision_data:AllSides()
	
	ComputeFall_velocity(Object, Mover_p, y_hit_level)

	--Come up with a formula to get MinN-MaxN sizes for magnitude and angles of the mover
	if (Mover_p-Sides.Top).Magnitude<=StudSteps then
		Mover.Position=V3(Mover_p.x,Sides.Top.y+Mover.Size.y/2,Mover_p.z)
	end
	if (Mover_p-Sides.Left).Magnitude<=StudSteps then
		Mover.Position=V3(Sides.Left.x+Mover.Size.x/-2,Mover_p.y,Mover.Position.z)
	end
	if (Mover_p-Sides.Front).Magnitude<=StudSteps then
		Mover.Position=V3(Mover_p.x,Mover_p.y,Sides.Front.z+Mover.Size.z/2)
	end
	
	if (Mover_p-Sides.Bottom).Magnitude<=StudSteps then
		Mover.Position=V3(Mover_p.x,Sides.Bottom.y-Mover.Size.y/2,Mover_p.z)
	end
	if (Mover_p-Sides.Right).Magnitude<=StudSteps then
		Mover.Position=V3(Sides.Right.x-Mover.Size.x/-2,Mover_p.y,Mover_p.z)
	end
	if (Mover_p-Sides.Back).Magnitude<=StudSteps then
		Mover.Position=V3(Mover_p.x,Mover_p.y,Sides.Back.z-Mover.Size.z/2)
	end

	if Hit_Indicators then
		if HitColliders.inv_y[Object] then
			HitColliders.inv_y[Object].Position = inv_y_hit_level
		end
		if HitColliders.y[Object] then
			HitColliders.y[Object].Position = y_hit_level
		end
		if HitColliders.x[Object] then
			HitColliders.x[Object].Position = x_hit_level
		end
		if HitColliders.inv_x[Object] then
			HitColliders.inv_x[Object].Position = inv_x_hit_level
		end
		if HitColliders.z[Object] then
			HitColliders.z[Object].Position = z_hit_level
		end
		if HitColliders.inv_z[Object] then
			HitColliders.inv_z[Object].Position = inv_z_hit_level
		end
	end
end

Heartbeat.TickStep:Connect(function(tdt,dt)
	thread(function()
		--Grab the physics info after a physics step
		PhysicsList = PhysicsList_Remote:InvokeServer()
	end)
	for i = 1, #PhysicsList do
		local Object = PhysicsList[i]
		local o_s, m_p = Object.Size, Mover.Position
		--This still needs a proper system
		local Prox = o_s.y/2<m_p.y/2 or o_s.x/-2<m_p.x/-2 or o_s.z/2<m_p.z/2

		if Object.Name == "Baseplate" then
			--print("Object=",o_s.y,"Mover=",m_p.y/2)
		end

		if Prox then
			ComputePhysics(Object, o_p)
		end
		if m_p.y<=workspace.FallenPartsDestroyHeight then
			Reset()
		end
	end
	PhysicsFPS_Remote:Fire(dt)
end)

thread(function()
	repeat
		task.wait()
	until #PhysicsList ~= 0
	for i = 1, #PhysicsList do
		local Obj = PhysicsList[i]
		Visual_HitCollisions('y',Obj,Color3.new(1,1,0),CN(0,Obj.Size.y/2,0).p)
		Visual_HitCollisions('inv_y',Obj,Color3.new(0,0,1),CN(0,Obj.Size.y/-2,0).p)
		Visual_HitCollisions('z',Obj,Color3.new(1,0,0),CN(Obj.Size.x/-2,0,0).p,ANG(pi/2,0,0))
		Visual_HitCollisions('inv_z',Obj,Color3.new(0,1,0),CN(Obj.Size.x/2,0,0).p,ANG(pi/-2,0,0))
		Visual_HitCollisions('x',Obj,Color3.new(1,0,1),CN(Obj.Size.x/2,0,0).p,ANG(0,0,pi/-2))
		Visual_HitCollisions('inv_x',Obj,Color3.new(0,1,1),CN(Obj.Size.x/2,0,0).p,ANG(0,0,pi/2))
	end
end)