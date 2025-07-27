local raceINI = ac.INIConfig.raceConfig()

local carDescription
---@return string|nil
local function getCarDescription()
  if not carDescription then
    if loading.carID() == '' then return nil end
    local description = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. loading.carID() .. '/ui/ui_car.json')).description
    carDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '')
  end
  return carDescription
end

local trackDescription
---@return string|nil
local function getTrackDescription()
  if not trackDescription then
    if loading.trackID() == '' then return nil end
    local path = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. loading.trackID() .. '/ui/'
    if loading.trackLayoutID() ~= '' then
      path = path .. loading.trackLayoutID() .. '/'
    end
    local description = JSON.parse(io.load(path .. 'ui_track.json')).description
    trackDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '')
  end
  return trackDescription
end

---@param size vec2
---@return string
local function getContentKey(size)
  local title, details = loading.warning()
  return string.format('%s|%s|%s|%s|%s|%s',
    title or '',
    #loading.serverHints(),
    loading.carName(),
    loading.trackName(),
    loading.version(),
    size.x
  )
end

---@param icon string
---@param iconPadding number
---@param title string
---@param detailsCallback function
local function drawBlock(icon, iconPadding, title, detailsCallback)
  if title == '' then return end

  ui.offsetCursorY(30)
  ui.dummy(vec2(64, 64))
  local r1, r2 = ui.itemRect()
  ui.drawIcon(icon, r1 + iconPadding, r2 - iconPadding)
  ui.sameLine(0, 12)
  ui.pushDWriteFont('@System;Weight=Bold')
  ui.dwriteText(title, 20)
  ui.popDWriteFont()
  ui.offsetCursorX(64 + 12)
  ui.offsetCursorY(-38)
  ui.dwriteTextWrapped(detailsCallback() or 'No description.', 14)
end

---@param hints table
---@param startIndex number|nil
---@return string
local function formatHints(hints, startIndex)
  startIndex = startIndex or 1
  return table.concat(table.map(hints, function(item, key)
    if key < startIndex then return nil end
    return '• %s' % item
  end), '\n')
end

---@return string
local function getSessionType()
  return raceINI:get('REMOTE', 'SERVER_NAME', '') and 'Singleplayer Session' or 'Online Session'
end

local simpleSession = false
local function generateContent()
  local title, details = loading.warning()
  if title then
    drawBlock(ui.Icons.Warning, 20, 'Warning', function()
      return title .. '\n' .. details
    end)
  end

  local serverHints = loading.serverHints()
  if #serverHints > 0 then
    drawBlock('splashscreen::logo', 8, raceINI:get('REMOTE', 'SERVER_NAME', ''), function()
      return formatHints(serverHints, 2)
    end)
  else
    drawBlock('splashscreen::logo', 8, getSessionType(), function()
      simpleSession = true
      return loading.version():replace('&', '\n&')
    end)
  end

  drawBlock('splashscreen::badge', 8, loading.carName(), function()
    local carHints = loading.carHints()
    if #carHints > 0 then
      return formatHints(carHints)
    end
    return getCarDescription()
  end)

  drawBlock('splashscreen::track', 8, loading.trackName(), getTrackDescription)

  if not simpleSession then
    drawBlock('splashscreen::logo', 8, 'Game Information', function()
      return "• " .. loading.version():replace('&', '\n• ')
    end)
  end
end

---@param infoWidth number
---@return number
local function measureContentHeight(infoWidth)
  ui.pushClipRect(vec2(-1000, -1000), vec2(-999, -999))
  ui.setCursor(vec2(0, 0))
  ui.beginGroup(infoWidth)
  generateContent()
  local height = ui.getCursorY()
  ui.endGroup()
  ui.popClipRect()
  return height
end

local bgColor = rgbm(0.2, 0.2, 0.2, 1)
---@param size vec2
---@param bgWidth number
---@param infoWidth number
local function drawBackground(size, bgWidth, infoWidth)
  ui.drawImage('splashscreen::background', 0, size, ui.ImageFit.Fill)
  ui.beginTextureShade('splashscreen::background')
  ui.beginMIPBias()
  ui.drawRectFilledMultiColor(vec2(infoWidth, 0), vec2(bgWidth, size.y),
    rgbm.colors.transparent, bgColor, bgColor, rgbm.colors.transparent)
  if size.x > bgWidth then
    ui.drawRectFilled(vec2(bgWidth, 0), size, bgColor)
  end
  ui.endTextureShade(vec2(0, 0), size)
  ui.endMIPBias(8, true)
end

local loadingStatus ---@type ui.ExtraCanvas
---@param size vec2
---@param padding number
local function drawLoadingBar(size, padding)
  if not loadingStatus or loadingStatus:size().x ~= size.x then
    loadingStatus = ui.ExtraCanvas(vec2(size.x, padding))
  end

  loadingStatus:clear(rgbm.colors.black):update(function()
    local start = ui.getCursor()
    ui.drawLoadingSpinner(start, start + vec2(20, 20))
    ui.offsetCursorX(28)
    ui.offsetCursorY(-1)
    ui.dwriteText(loading.status(), 16)
    ui.sameLine(0, 8)
    ui.dwriteText(loading.details(), 16, rgbm.colors.gray)
  end)

  local pos = vec2(0, size.y - padding)
  ui.beginRotation()
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size())
  ui.setShadingOffset(-1, 1, 1, 1)
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size() * vec2(loading.progress(), 1),
    rgbm.colors.white, vec2(), vec2(loading.progress(), 1), ui.ImageFit.Fill)
  ui.resetShadingOffset()
  ui.endRotation(90, 0)
end

local contentHeight
local lastContentKey
---@param size vec2
---@param infoWidth number
---@param padding number
local function drawContent(size, infoWidth, padding)
  local contentKey = getContentKey(size)
  if not contentHeight or lastContentKey ~= contentKey then
    contentHeight = measureContentHeight(infoWidth)
    lastContentKey = contentKey
  end

  local startY = math.max(20, (size.y - contentHeight) / 2)
  ui.setCursor(vec2(size.x - infoWidth - padding / 2, startY))
  ui.beginGroup(infoWidth)
  generateContent()
  ui.endGroup()
end

local padding = 20
local bgRatio = 0.7
local infoRatio = 1 - bgRatio
function script.update()
  local size = ui.windowSize()
  local bgWidth = size.x * bgRatio
  local infoWidth = size.x * infoRatio

  drawBackground(size, bgWidth, infoWidth)
  drawLoadingBar(size, padding)
  drawContent(size, infoWidth, padding)
end
