local bgRatio = 0.7
local size = vec2()
local bgWidth = size.x * bgRatio
local infoWidth = size.x * (1 - bgRatio)
local bgColor = rgbm(0.3, 0.3, 0.3, 1)
local padding = 20

local carDescription, carName, trackDescription, loadingStatus, gameInfoText, lastContentKey
local contentCache = {}

local raceINI = ac.INIConfig.raceConfig()
local weatherfxImpl = ac.INIConfig.load(ac.getFolder(ac.FolderID.ExtCfgUser) .. '\\weather_fx.ini'):get('BASIC', 'IMPLEMENTATION', 'Default')
--ac.getPpFilter():gsub('[_%-]', ' '):gsub('%.ini$', '') used to work, doesnt anymore?, im just gonna do this instead, seems to work just fine
local ppFilter = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg) .. '\\video.ini'):get('POST_PROCESS', 'FILTER', 'Default'):gsub('[_%-]', ' ')
local patchVersion = ac.getPatchVersionCode()

---@return string|nil, string|nil
---@param infoType string
local function getCarInformation(infoType)
  if type(infoType) ~= 'string' then return nil end
  local carID = raceINI:get('RACE', 'MODEL', '')
  if carID == '' then return nil end
  if not carName or not carDescription then
    local carData = JSON.parse(io.load(ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/ui/ui_car.json'))
    carName = carData.name
    local specs = carData.specs
    if specs then
      carDescription = string.format('• Power: %-20s  Torque: %s\n• Weight: %-20s P/W Ratio: %s\n• Top Speed: %-12s  0–100: %s',
        specs.bhp or 'N/A',
        specs.torque or 'N/A',
        specs.weight or 'N/A',
        specs.pwratio or 'N/A',
        specs.topspeed or 'N/A',
        specs.acceleration or 'N/A')
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
local function getTrackDescription()
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

---@param size vec2
---@return string
local function getContentKey(size)
  local title, details = loading.warning()
  return string.format('%s|%d|%s|%s|%s|%d', title or '', #loading.serverHints(), loading.carName(), loading.trackName(), loading.version(), size.x)
end

---@param icon ui.Icons
---@param iconPadding number
---@param title string
---@param details string
local function drawBlock(icon, iconPadding, title, details)
  if title == '' then return end
  ui.offsetCursorY(15)
  ui.dummy(vec2(64, 64))
  local r1, r2 = ui.itemRect()
  ui.drawIcon(icon, r1 + iconPadding, r2 - iconPadding)
  ui.sameLine(0, 12)
  ui.pushDWriteFont('@System;Weight=Bold')
  ui.dwriteTextWrapped(title, 20)
  local infoWrap = infoWidth - 64 - 12
  local singleLineHeight = math.floor(ui.measureDWriteText('Singleline', 20, infoWrap).y)
  local totalTitleHeight = ui.measureDWriteText(title, 20, infoWrap).y
  local extraLines = math.min(2, (totalTitleHeight - singleLineHeight) / singleLineHeight)
  ui.popDWriteFont()
  ui.offsetCursorX(64 + 12)
  ui.offsetCursorY(-math.ceil((38 - (extraLines * singleLineHeight))))
  ui.dwriteTextWrapped(details or 'No description.', 14)
end

---@param hints string[]
---@param startIndex number?
---@return string
local function formatHints(hints, startIndex)
  local result = {}
  for i = startIndex or 1, #hints do result[#result + 1] = '• ' .. hints[i] end
  return table.concat(result, '\n')
end

---@return string
local function buildGameInfo()
  if not gameInfoText then
    gameInfoText = table.concat({ '• ' .. loading.version():replace('&', '\n•') .. ' (' .. patchVersion .. ')', '• PP Filter: ' .. ppFilter, '• Weather FX: ' .. weatherfxImpl }, '\n')
  end
  return gameInfoText
end

local function generateContent()
  local blocks = {}
  local title, details = loading.warning()
  if title then blocks[#blocks + 1] = { ui.Icons.Warning, 20, 'Warning', title .. '\n' .. details } end
  local serverHints = loading.serverHints()
  if #serverHints > 0 then
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, raceINI:get('REMOTE', 'SERVER_NAME', ''), formatHints(serverHints, 2) }
  else
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, 'Singleplayer Session', buildGameInfo() }
  end
  blocks[#blocks + 1] = { 'splashscreen::badge', 8, getCarInformation('name'), getCarInformation('description') }
  blocks[#blocks + 1] = { 'splashscreen::track', 8, loading.trackName(), getTrackDescription() }
  if #serverHints > 0 then
    blocks[#blocks + 1] = { 'splashscreen::logo', 8, 'Game Information', buildGameInfo() }
  end
  for i = 1, #blocks do drawBlock(blocks[i][1], blocks[i][2], blocks[i][3], blocks[i][4]) end
end

---@return number
local function measureContentHeight()
  ui.pushClipRect(vec2(-1000, -1000), vec2(-999, -999))
  ui.setCursor(vec2(0, 0))
  ui.beginGroup(infoWidth)
  generateContent()
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
  if not loadingStatus or loadingStatus:size().x ~= size.x then loadingStatus = ui.ExtraCanvas(vec2(size.x, padding)) end
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
  ui.drawImage(loadingStatus, pos, pos + loadingStatus:size() * vec2(loading.progress(), 1), rgbm.colors.white, vec2(), vec2(loading.progress(), 1), ui.ImageFit.Fill)
  ui.resetShadingOffset()
  ui.endRotation(90, 0)
end

local function drawContent()
  local contentKey = getContentKey(size)
  if not contentCache[contentKey] then
    contentCache[contentKey] = measureContentHeight()
    if lastContentKey and lastContentKey ~= contentKey then contentCache[lastContentKey] = nil end
    lastContentKey = contentKey
  end
  local startY = math.max(20, (size.y - contentCache[contentKey]) / 2)
  ui.setCursor(vec2(size.x - infoWidth - padding / 2, startY))
  ui.beginGroup(infoWidth)
  generateContent()
  ui.endGroup()
end

function script.update()
  size = ui.windowSize()
  bgWidth = size.x * bgRatio
  infoWidth = size.x * (1 - bgRatio)
  drawBackground()
  drawLoadingBar()
  drawContent()
end
