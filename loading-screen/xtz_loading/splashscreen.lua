local size = vec2()
local bgWidth = 0
local infoWidth = 0
local scaleRatio = 1
local bgColor = rgbm(0.3, 0.3, 0.3, 1)
local padding = 20
local contentCache = {}

local carDescription, carName, trackDescription, loadingStatus, gameInfoText, lastContentKey

local raceINI = ac.INIConfig.raceConfig()
local weatherfxImpl = ac.INIConfig.load(ac.getFolder(ac.FolderID.ExtCfgUser) .. '\\weather_fx.ini'):get('BASIC', 'IMPLEMENTATION', 'Default')
local ppFilter = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg) .. '\\video.ini'):get('POST_PROCESS', 'FILTER', 'Default'):gsub('[_%-]', ' ')
local patchVersion = ac.getPatchVersionCode()

---@param value number
---@return number
local function scale(value) return math.floor(value * scaleRatio) end

---@param infoType string
---@return string|nil, string|nil, table|nil
local function buildCarInfo(infoType)
  if type(infoType) ~= 'string' then return nil end
  local carID = raceINI:get('RACE', 'MODEL', '')
  if carID == '' then return nil end
  if not carName or not carDescription then
    local carData = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/ui/ui_car.json'))
    carName = carData.name
    local specs = carData.specs
    if specs then
      carDescription = {
        { '• Power: ' .. (specs.bhp or 'N/A'), '• Torque: ' .. (specs.torque or 'N/A') },
        { '• Weight: ' .. (specs.weight or 'N/A'), '• P/W Ratio: ' .. (specs.pwratio or 'N/A') },
        { '• Top Speed: ' .. (specs.topspeed or 'N/A'), '• 0-100: ' .. (specs.acceleration or 'N/A') }
      }
    else
      carDescription = string.reggsub(carData.description, [[\t|</?br\s*/?\s*>]], '\n')
    end
  end
  if infoType == 'name' then
    return carName
  elseif infoType == 'description' then
    return carDescription
  end
end

---@return string|nil
local function buildTrackInfo()
  if not trackDescription then
    local trackID = loading.trackID()
    if trackID == '' then return nil end
    local path = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. trackID .. '/ui/'
    local layoutID = loading.trackLayoutID()
    if layoutID ~= '' then path = path .. layoutID .. '/' end
    local description = JSON.parse(io.load(path .. 'ui_track.json')).description
    trackDescription = string.reggsub(description, [[\t|</?br\s*/?\s*>]], '\n')
  end
  return trackDescription
end

---@return string
local function buildContentKey()
  local title, details = loading.warning()
  return table.concat({
      title or '',
      #loading.serverHints(),
      loading.carName(),
      loading.trackName(),
      loading.version(),
      size.x },
    '|')
end

---@param icon ui.Icons
---@param iconPadding number
---@param title string
---@param details string|table
local function drawBlock(icon, iconPadding, title, details)
  if title == '' then return end
  ui.offsetCursorY(scale(15))
  ui.dummy(vec2(64, 64):scale(scaleRatio))
  local r1, r2 = ui.itemRect()
  ui.drawIcon(icon, r1 + scale(iconPadding), r2 - scale(iconPadding))
  ui.sameLine(0, scale(12))
  ui.pushDWriteFont('@System;Weight=Bold')
  ui.dwriteTextWrapped(title, scale(20))
  local infoWrap = infoWidth - scale(76)
  local singleLineHeight = math.floor(ui.measureDWriteText('Singleline', scale(20), infoWrap).y)
  local totalTitleHeight = ui.measureDWriteText(title, scale(20), infoWrap).y
  local extraLines = math.min(2, (totalTitleHeight - singleLineHeight) / singleLineHeight)
  ui.popDWriteFont()
  ui.offsetCursorX(scale(64) + scale(12))
  ui.offsetCursorY(-math.ceil((scale(38) - (extraLines * singleLineHeight))))
  if type(details) == 'table' then
    local halfWidth = infoWrap / 2
    local startX = ui.getCursorX()
    for i = 1, #details do
      ui.setCursorX(startX)
      ui.dwriteText(details[i][1], scale(14))
      ui.sameLine(halfWidth, 0)
      ui.dwriteText(details[i][2], scale(14))
    end
  else
    ui.dwriteTextWrapped(details or 'No description.', scale(14))
  end
end

---@param hints string[]
---@param startIndex number?
---@return string
local function buildHintsText(hints, startIndex)
  local result = {}
  for i = startIndex or 1, #hints do result[#result + 1] = '• ' .. hints[i] end
  return table.concat(result, '\n')
end

---@return string
local function buildGameInfo()
  if not gameInfoText then
    gameInfoText = table.concat({
        '• ' .. loading.version():replace('&', '\n•') .. ' (' .. patchVersion .. ')',
        '• PP Filter: ' .. ppFilter, '• Weather FX: ' .. weatherfxImpl },
      '\n')
  end
  return gameInfoText
end

local function buildContent()
  local blocks = {}
  local title, details = loading.warning()
  if title then blocks[#blocks + 1] = { ui.Icons.Warning, 20, 'Warning', title .. '\n' .. details } end
  local serverHints = loading.serverHints()
  if #serverHints > 0 then
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, raceINI:get('REMOTE', 'SERVER_NAME', ''), buildHintsText(serverHints, 2) }
  else
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, 'Singleplayer Session', buildGameInfo() }
  end
  blocks[#blocks + 1] = { 'splashscreen::badge', 8, buildCarInfo('name'), buildCarInfo('description') }
  blocks[#blocks + 1] = { 'splashscreen::track', 8, loading.trackName(), buildTrackInfo() }
  if #serverHints > 0 then
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, 'Game Information', buildGameInfo() }
  end
  for i = 1, #blocks do drawBlock(blocks[i][1], blocks[i][2], blocks[i][3], blocks[i][4]) end
end

---@return number
local function buildContentHeight()
  ui.pushClipRect(vec2(-1000, -1000), vec2(-999, -999))
  ui.setCursor(vec2(0, 0))
  ui.beginGroup(infoWidth)
  buildContent()
  local height = ui.getCursorY()
  ui.endGroup()
  ui.popClipRect()
  return height
end

local function drawBackground()
  ui.drawImage('splashscreen::background', 0, size, ui.ImageFit.Fill)
  ui.beginTextureShade('splashscreen::background')
  ui.beginMIPBias()
  ui.drawRectFilledMultiColor(vec2(infoWidth, 0), vec2(bgWidth, size.y), rgbm.colors.transparent, bgColor, bgColor, rgbm.colors.transparent)
  if size.x > bgWidth then ui.drawRectFilled(vec2(bgWidth, 0), size, bgColor) end
  ui.endTextureShade(vec2(0, 0), size)
  ui.endMIPBias(8, true)
end

local function drawLoadingBar()
  if not loadingStatus or loadingStatus:size().x ~= size.x then loadingStatus = ui.ExtraCanvas(vec2(size.x, scale(padding))) end
  loadingStatus:clear(rgbm.colors.black):update(function()
    local start = ui.getCursor()
    ui.drawLoadingSpinner(start, start + vec2(20, 20):scale(scaleRatio))
    ui.offsetCursorX(scale(28))
    ui.offsetCursorY(scale(-1))
    ui.dwriteText(loading.status(), scale(16))
    ui.sameLine(0, scale(8))
    ui.dwriteText(loading.details(), scale(16), rgbm.colors.gray)
  end)
  local pos = vec2(0, size.y - scale(padding))
  ui.beginRotation()
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size())
  ui.setShadingOffset(scale(-1), scale(1), scale(1), scale(1))
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size() * vec2(loading.progress(), 1), rgbm.colors.white, vec2(), vec2(loading.progress(), 1), ui.ImageFit.Fill)
  ui.resetShadingOffset()
  ui.endRotation(90, 0)
end

local function drawContent()
  local contentKey = buildContentKey()
  if not contentCache[contentKey] then
    contentCache[contentKey] = buildContentHeight()
    if lastContentKey and lastContentKey ~= contentKey then contentCache[lastContentKey] = nil end
    lastContentKey = contentKey
  end
  local startY = math.max(scale(20), (size.y - contentCache[contentKey]) / 2)
  ui.setCursor(vec2(size.x - infoWidth - scale(padding) / 2, startY))
  ui.beginGroup(infoWidth)
  buildContent()
  ui.endGroup()
end

local function buildLayout()
  local baseInfoWidth = 1920 * 0.3
  infoWidth = scale(baseInfoWidth)
  bgWidth = size.x - infoWidth
end

function script.update()
  size = ui.windowSize()
  scaleRatio = size.y / 1080
  buildLayout()
  drawBackground()
  drawLoadingBar()
  drawContent()
end
