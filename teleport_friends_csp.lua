-- TELEPORT FRIENDS - ONLINE CSP APP
-- FastTravel ghost/collision sistemi entegre edilmiştir.
--
-- Özellikler:
--   * Kendi aracını listelemez.
--   * Online oyuncuları otomatik listeler.
--   * Oyuncu adına basınca aracın arkasına teleport eder.
--   * Teleporttan HEMEN ÖNCE collision/ghost açılır.
--   * FastTravel ile aynı mantıkla OnlineEvent üzerinden senkronize edilir.
--   * Ghost en az 5 saniye tutulur.
--   * 5 saniye sonunda başka araca hâlâ çok yakınsan ghost uzatılır.
--   * Güvenli mesafeye çıkınca collision tekrar açılır.

local TELEPORT_DISTANCE = 5.0
local REFRESH_INTERVAL = 0.5

local players = {}
local refreshTimer = 0.0
local message = ''
local messageTimer = 0.0

-- ============================================================
-- FASTTRAVEL GHOST / COLLISION SYSTEM
-- ============================================================

-- FastTravel'daki API kontrolünün aynısı:
local supportAPI_collision = physics.disableCarCollisions ~= nil

local disabledCollision = false
local teleportEstimate = 999.0

local function say(text)
  message = text
  messageTimer = 2.5
end

-- FastTravel mantığındaki online collision event.
-- Aynı app'i kullanan diğer oyunculara collision durumunu bildirir.
local disabledCollisionEvent = ac.OnlineEvent({
  ac.StructItem.key('TeleportFriendsDisabledCollision'),
  disabled = ac.StructItem.boolean()
}, function(sender, data)
  if sender == nil then return end
  if sender.index == 0 then return end

  if supportAPI_collision then
    physics.disableCarCollisions(sender.index, data.disabled)
    physics.disableCarCollisions(0, data.disabled)
  end
end)

-- Collision kapat/aç.
local function setGhost(enabled)
  if not supportAPI_collision then
    return false
  end

  local ok = pcall(function()
    physics.disableCarCollisions(0, enabled)
  end)

  return ok
end

-- FastTravel'daki başlangıç davranışı:
-- teleporttan hemen önce collision kapatılır ve event gönderilir.
local function beginGhost()
  if supportAPI_collision then
    pcall(function()
      physics.disableCarCollisions(0, true)
    end)
  end

  disabledCollisionEvent({ disabled = true })
  disabledCollision = true
  teleportEstimate = 0.0
end

-- Teleport başarısız olursa veya güvenli hale gelince collision açılır.
local function endGhost()
  if not disabledCollision then
    return
  end

  if supportAPI_collision then
    pcall(function()
      physics.disableCarCollisions(0, false)
    end)
  end

  disabledCollisionEvent({ disabled = false })
  disabledCollision = false
end

-- FastTravel'daki kontrolün aynısı:
-- En az 5 saniye ghost tutulur.
-- Sonrasında başka araç çok yakınsa ghost devam eder.
local function updateGhost(dt)
  if not disabledCollision then
    return
  end

  teleportEstimate = teleportEstimate + dt

  if teleportEstimate <= 5.0 then
    return
  end

  local sim = ac.getSim()
  if not sim then
    return
  end

  local myCar = ac.getCar(0)
  if not myCar then
    return
  end

  local closer = false
  local count = tonumber(sim.carsCount) or 0

  for i = 1, count - 1 do
    local carState = ac.getCar(i)

    if carState then
      local dist = carState.position:distance(myCar.position)

      -- FastTravel'daki aynı yakınlık kontrolü.
      if dist < (carState.aabbSize.z / 2) then
        closer = true

        -- FastTravel'daki uzatma davranışı:
        -- süre tekrar 5 saniyelik kontrol penceresine düşürülür.
        teleportEstimate = teleportEstimate - 1.0
        break
      end
    end
  end

  if not closer then
    endGhost()
  end
end

-- ============================================================
-- ONLINE PLAYER LIST
-- ============================================================

local function refreshPlayers()
  table.clear(players)

  local sim = ac.getSim()
  if not sim then
    return
  end

  -- Kendi aracımızı (Car 0) listeleme.
  -- Sadece sunucudaki diğer oyuncuların driverName değerlerini göster.
  local count = tonumber(sim.carsCount) or 0

  for i = 1, count - 1 do
    local ok, car = pcall(function()
      return ac.getCar(i)
    end)

    if ok and car then
      local okName, name = pcall(function()
        return car:driverName()
      end)

      if okName and name ~= nil and name ~= '' then
        players[#players + 1] = {
          index = i,
          name = name
        }
      end
    end
  end

  table.sort(players, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
end

-- ============================================================
-- TELEPORT
-- ============================================================


local function teleportBehind(carIndex, playerName)
  if not physics.allowed() then
    say('Extended Physics gerekli.')
    return
  end

  local okTarget, target = pcall(function()
    return ac.getCar(carIndex)
  end)

  if not okTarget or not target then
    say(playerName .. ' artık online değil.')
    refreshPlayers()
    return
  end

  local okLook, look = pcall(function()
    return target.look:clone()
  end)

  if not okLook or not look then
    say('Hedef yönü alınamadı.')
    return
  end

  -- Hedefin yatay yönünü al.
  look.y = 0

  if look:lengthSquared() < 0.0001 then
    say('Hedef yönü geçersiz.')
    return
  end

  look = look:normalize()

  -- Hedefin arkasına yerleş.
  local destination = target.position - look * TELEPORT_DISTANCE
  destination.y = target.position.y

  -- ==========================================================
  -- ÖNCE GHOST
  -- FastTravel'daki gibi teleporttan önce collision kapat.
  -- ==========================================================
  beginGhost()

  -- physics.setCarPosition() yön vektörünü ters kabul ediyor.
  -- Bu yüzden aracın gerçek gidiş yönünü korumak için -look gönderiyoruz.
  local teleportDirection = -look

  local okTeleport, err = pcall(function()
    physics.setCarPosition(0, destination, teleportDirection)
  end)

  if not okTeleport then
    endGhost()
    say('TELEPORT HATASI: ' .. tostring(err))
    return
  end

  say(string.format('Teleport → %s | Ghost aktif', playerName))
end

-- ============================================================
-- UI
-- ============================================================

local teleportApp = ui.addSettings({
  id = 'TeleportFriendsOnlineApp',
  name = 'Teleport Friends',
  icon = ui.Icons.Car,
  category = 'main',
  size = {
    default = vec2(360, 430),
    min = vec2(280, 260),
    max = vec2(700, 800)
  }
}, function()
  ui.text('')
  ui.separator()

  if messageTimer > 0 then
    ui.text(message)
    ui.offsetCursorY(4)
  end

  ui.text('ONLINE: ' .. tostring(#players))

  if supportAPI_collision then
    if disabledCollision then
      ui.text(string.format(
        'GHOST: AKTİF (%.1fs)',
        math.max(0.0, 5.0 - teleportEstimate)
      ))
    else
      ui.text()
    end
  else
    ui.text('GHOST API: YOK')
  end

  ui.offsetCursorY(8)

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

          -- Liste elemanlarını normalde neredeyse görünmez yap.
          -- Mouse üstüne gelince arka plan ve yazı belirginleşir.
          ui.pushStyleColor(ui.StyleColor.Button, rgbm(1, 1, 1, 0.015))
          ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(1, 1, 1, 0.16))
          ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(1, 1, 1, 0.24))
          ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 0.10))
          ui.pushStyleColor(ui.StyleColor.TextHovered, rgbm(1, 1, 1, 0.95))

          if ui.button(
            '●  ' .. player.name,
            vec2(ui.availableSpaceX(), 34)
          ) then
            teleportBehind(player.index, player.name)
          end

          ui.popStyleColor(5)

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

-- ============================================================
-- UPDATE
-- ============================================================

function script.update(dt)
  -- Online oyuncu listesini yenile.
  refreshTimer = refreshTimer - dt

  if refreshTimer <= 0 then
    refreshTimer = REFRESH_INTERVAL

    -- Liste hatası yüzünden uygulamanın tamamen durmasını önle.
    pcall(refreshPlayers)
  end

  if messageTimer > 0 then
    messageTimer = math.max(0.0, messageTimer - dt)
  end

  -- FastTravel ghost/collision kontrolü.
  updateGhost(dt)
end
