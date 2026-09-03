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

  ui.popStyleVar()
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
  -- Sistem Car 0'ı kullanmaya devam eder; sadece UI'da kendi adımız gösterilmez.
  -- Böylece her oyuncu yalnızca diğer online oyuncuları görür.
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
  -- Araç hareket halindeyken teleportu engelle.
  -- 1 km/h üzerindeyse teleport yapılmaz.
  local myCar = ac.getCar(0)

  if myCar then
    local speed = tonumber(myCar.speedKmh) or 0

    if speed > 1.0 then
      say(string.format('Teleport kapalı: araç hareket ediyor (%.1f km/h)', speed))
      return
    end
  end

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

-- Chat benzeri arka plan saydamlığı
local windowBackgroundAlpha = ui.SmoothInterpolation(1.0, 2.0)
local windowContentAlpha = ui.SmoothInterpolation(1.0, 2.0)
local ACTIVE_BACKGROUND_ALPHA = 0.30
local INACTIVE_BACKGROUND_ALPHA = 0.0

-- Ana pencerenin içindeki child/list alanı için ayrı hover durumu.
-- ui.windowHovered() ana pencere yerine child window üzerinde çalışabildiği
-- için bir önceki frame'deki child hover bilgisini de saklıyoruz.
local listHovered = false

local teleportApp = ui.addSettings({
  id = 'TeleportFriendsOnlineApp',
  name = 'Teleport Friends',
  icon = ui.Icons.Car,
  category = 'main',
  flags = {'NO_BACKGROUND', 'FLOATING_TITLE_BAR', 'FADING'},
  size = {
    default = vec2(360, 430),
    min = vec2(280, 260),
    max = vec2(700, 800)
  }
}, function()
  -- CSP'nin kendi app arka planını kapatıyoruz.
  -- Arka planı burada kendimiz çizip sadece mouse üstündeyken görünür yapıyoruz.
  -- Ana pencere veya bir önceki frame'de liste/child alanı hover ise
  -- uygulama aktif kabul edilir.
  local hovered = ui.windowHovered() or listHovered
  local targetAlpha = hovered and ACTIVE_BACKGROUND_ALPHA or INACTIVE_BACKGROUND_ALPHA
  local alpha = windowBackgroundAlpha(targetAlpha)

  -- Mouse pencerenin/oyuncu listesinin dışına çıkınca içerik de tamamen kaybolsun.
  local contentAlpha = windowContentAlpha(hovered and 1.0 or 0.0)

  ui.drawRectFilled(
    vec2(0, 0),
    vec2(ui.windowWidth(), ui.windowHeight()),
    rgbm(0, 0, 0, alpha)
  )

  -- Mouse dışındayken listenin/yazıların tamamen kaybolması.
  ui.pushStyleVarAlpha(contentAlpha)

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

  -- Bu frame'de child alanı çizilene kadar önceki durum kullanılır.
  -- Liste yoksa eski hover durumu kalmasın.
  if #players == 0 then
    listHovered = false
    ui.text('Başka online oyuncu yok.')
  else
    ui.childWindow(
      'TeleportFriendsOnlineList',
      vec2(ui.availableSpaceX(), ui.availableSpaceY()),
      true,
      function()
        -- Mouse liste/child alanının boş kısmında olsa bile pencere
        -- hover kabul edilsin.
        listHovered = ui.windowHovered()

        for _, player in ipairs(players) do
          ui.pushID(player.index)

          if ui.button(
            '👥  ' .. player.name,
            vec2(ui.availableSpaceX(), 34)
          ) then
            teleportBehind(player.index, player.name)
          end

          ui.offsetCursorY(4)
          ui.popID()
        end
      end
    )
  end

  ui.popStyleVar()
end)


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
