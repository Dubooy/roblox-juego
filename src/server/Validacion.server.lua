-- Validación básica en el servidor. El cliente mueve su personaje (así se siente
-- instantáneo), y el servidor comprueba que no vaya más rápido de lo posible.
-- De momento solo avisa en la consola; en PvP aquí se devolvería al jugador a su
-- última posición válida.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

workspace.Gravity = C.GRAVITY

local INTERVALO = 0.25
local AVISOS_PARA_MARCAR = 4
local limite = math.max(C.MAX_SPEED, C.MANOTAZO_EMPUJE + C.MAX_SPEED * C.MANOTAZO_EMPUJE_EXTRA_VEL) * C.SERVER_SPEED_TOLERANCE

local registro = {} -- [player] = { pos, avisos }

Players.PlayerAdded:Connect(function(player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CharacterAdded:Connect(function()
		registro[player] = nil -- al reaparecer se teletransporta; no contar ese salto
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	registro[player] = nil
end)

while true do
	task.wait(INTERVALO)
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		local pos = root.Position
		local r = registro[player]
		if r and not root:GetAttribute("Teletransportado") then
			local d = Vector3.new(pos.X - r.pos.X, 0, pos.Z - r.pos.Z).Magnitude
			if d / INTERVALO > limite then
				r.avisos += 1
				if r.avisos >= AVISOS_PARA_MARCAR then
					warn(("[Movimiento] %s va demasiado rápido (%.0f studs/s)"):format(player.Name, d / INTERVALO))
					r.avisos = 0
				end
			else
				r.avisos = math.max(0, r.avisos - 1)
			end
			r.pos = pos
		else
			root:SetAttribute("Teletransportado", nil)
			registro[player] = { pos = pos, avisos = 0 }
		end
	end
end
