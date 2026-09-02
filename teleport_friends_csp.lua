-- TELEPORT FRIENDS - ONLINE CSP APP
--
-- Özellikler:
--   * Kendi aracını listede göstermez.
--   * Sunucudaki diğer sürücülerin isimlerini otomatik listeler.
--   * İsimlere tıklayarak hedef aracın arkasına teleport olur.
--   * Teleport sonrası kısa süreli ghost/collision kapatma uygular.
--   * Oyuncu çıkınca liste otomatik güncellenir.

local TELEPORT_DISTANCE = 5.0
local GHOST_DURATION = 1.5
local REFRESH_INTERVAL = 0.5

local players = {}
local refreshTimer = 0.0
local message = ''
local messageTimer = 0.0
local ghostTimer = 0.0
local ghostActive = false
local ghostApiAvailable = false

local function say(text)
  message = text
  messageTimer = 2.5
end

-- CSP sürümlerinde collision kontrolü farklı isimle bulunabiliyor.
-- Önce güncel fonksiyonu, sonra uyumluluk için alternatif ismi dener.
local function setGhost(enabled)
  local ok = false

  if physics.setCarCollisionEnabled ~= nil then
    ok = pcall(function()
      physics.setCarCollisionEnabled(0, enabled)
    end)
  end

  if not ok and physics.setCarCollision ~= nil then
    ok = pcall(function()
      physics.setCarCollision(0, enabled)
    end)
  end

  if ok then
    ghostApiAvailable = true
  end

  return ok
end

local function refreshPlayers()
  table.clear(players)

  -- ac.iterateCars() multiplayer oturumundaki araçları verir.
  -- index 0 her zaman yerel oyuncu olduğu için özellikle atlanır.
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

  -- Hedefin arkasında, hedefle aynı yükseklikte bir nokta.
  local destination = target.position - look * TELEPORT_DISTANCE
  destination.y = target.position.y

  -- Ghost'u teleporttan hemen önce açıyoruz; böylece varış anında
  -- başka araca çarpma ihtimali azaltılıyor.
  local ghostOK = setGhost(false)
  if ghostOK then
    ghostActive = true
    ghostTimer = GHOST_DURATION
  end

  physics.setCarPosition(0, destination, -look)

  if ghostOK then
    say(string.format('Teleport → %s  |  Ghost %.1fs', playerName, GHOST_DURATION))
  else
    say('Teleport → ' .. playerName .. '  |  Ghost API bulunamadı')
  end
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

  if ghostActive then
    ui.text(string.format('GHOST: %.1fs', math.max(0, ghostTimer)))
    ui.offsetCursorY(5)
  end

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
    refreshTimer = REFRESH_INTERVAL
    refreshPlayers()
  end

  if messageTimer > 0 then
    messageTimer = math.max(0, messageTimer - dt)
  end

  -- Ghost süresi dolunca collision tekrar açılır.
  if ghostActive then
    ghostTimer = ghostTimer - dt
    if ghostTimer <= 0 then
      ghostTimer = 0
      ghostActive = false
      if ghostApiAvailable then
        setGhost(true)
      end
    end
  end
end
