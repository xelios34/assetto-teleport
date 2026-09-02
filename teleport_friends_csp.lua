-- TELEPORT FRIENDS - ONLINE REAL CSP APP

local TELEPORT_DISTANCE = 5.0

local players = {}
local refreshTimer = 0.0
local message = ''
local messageTimer = 0.0

local function say(text)
  message = text
  messageTimer = 2.5
end

local function refreshPlayers()
  table.clear(players)

  for car in ac.iterateCars() do
    if car.index ~= 0 then
      local name = car:driverName()
      if name ~= nil and name ~= '' then
        players[#players + 1] = {
          index = car.index,
          name = name
        }
      end
    end
  end

  table.sort(players, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
end

local function teleportBehind(carIndex, playerName)
  if not physics.allowed() then
    say('Extended Physics gerekli.')
    return
  end

  local target = ac.getCar(carIndex)
  if not target then
    say(playerName .. ' artık online değil.')
    refreshPlayers()
    return
  end

  local look = target.look:clone()
  look.y = 0

  if look:lengthSquared() < 0.0001 then
    say('Hedef yönü alınamadı.')
    return
  end

  look = look:normalize()
  local destination = target.position - look * TELEPORT_DISTANCE
  destination.y = target.position.y
  physics.setCarPosition(0, destination, -look)
  say('Teleport → ' .. playerName)
end

local teleportApp = ui.addSettings({
  id = 'TeleportFriendsOnlineApp',
  name = 'Teleport Friends',
  icon = ui.Icons.Car,
  category = 'main',
  size = {
    default = vec2(320, 430),
    min = vec2(260, 240),
    max = vec2(700, 800)
  }
}, function()
  ui.text('TELEPORT FRIENDS')
  ui.separator()

  if messageTimer > 0 then
    ui.text(message)
  end

  ui.offsetCursorY(8)
  ui.text('ONLINE: ' .. tostring(#players))
  ui.offsetCursorY(5)

  if #players == 0 then
    ui.text('Başka online oyuncu yok.')
  else
    ui.childWindow(
      'TeleportFriendsOnlineList',
      vec2(ui.availableSpaceX(), ui.availableSpaceY()),
      true,
      function()
        for _, player in ipairs(players) do
          ui.pushID(player.index)
          if ui.button('●  ' .. player.name, vec2(ui.availableSpaceX(), 34)) then
            teleportBehind(player.index, player.name)
          end
          ui.offsetCursorY(4)
          ui.popID()
        end
      end
    )
  end
end)

if teleportApp then
  teleportApp('open')
end

function script.update(dt)
  refreshTimer = refreshTimer - dt
  if refreshTimer <= 0 then
    refreshTimer = 0.5
    refreshPlayers()
  end

  if messageTimer > 0 then
    messageTimer = math.max(0, messageTimer - dt)
  end
end
