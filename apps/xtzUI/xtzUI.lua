local config = {
    dimensions = {
        element = vec2(297, 85),
        rpmBar = { height = 10 },
        speed = { number = vec2(107, 48), text = vec2(85, 21) },
        inputBar = { position = vec2(46, -37), size = vec2(5, 43), spacing = 10 },
        indicator = vec2(55, 2),
        ping = {
            position = vec2(0, 18),
            offset = vec2(109, -12),
            bars = { count = 4, spacing = 5 }
        }
    },
    fonts = { bold = 'IBM Plex Sans:.\\src;Weight=Bold', black = 'IBM Plex Sans:.\\src;Weight=Black' },
    fontSizes = { speed = 34, unit = 14, gear = 60, ping = 18 },
    colors = {
        rpm = {
            { level = 0,  color = rgbm.colors.white:clone() },
            { level = 94, color = rgbm.colors.yellow:clone() },
            { level = 98, color = rgbm.colors.red:clone() }
        },
        halfBlack = rgbm(0, 0, 0, 0.5),
        white = rgbm.colors.white:clone(),
        gray = rgbm.colors.gray:clone(),
        yellow = rgbm.colors.yellow:clone(),
        red = rgbm.colors.red:clone(),
        lime = rgbm.colors.lime:clone(),
        aqua = rgbm.colors.aqua:clone()
    },
    indicator = { minWidth = 0.2, animDuration = 0.1, blinkDelay = 0.15 },
    flashState = {
        isFlashing = false,
        elapsedTime = 0,
        currentFlash = 0,
        isBeamOn = false
    }
}

local state = {
    center = vec2(0, 0),
    rpmBarColor = rgbm.colors.white:clone(),
    indicators = { left = { progress = 0, active = false }, right = { progress = 0, active = false }, phase = { time = nil, accumulator = 0 } },
    speedText = '0',
    gearText = 'N',
    lastSpeed = -1,
    lastGear = -1,
    lastRpmPercent = -1,
    speedTextWidth = 0,
    gearTextWidth = 0,
    inputBarPositions = {},
    tpButtonHeld = false,
    prevHighBeamButton = false,
    highBeamToggled = false,
}

local rpmColors = config.colors.rpm
local inputBarSpacing = config.dimensions.inputBar.spacing
local inputBarPos = config.dimensions.inputBar.position
local speedFontSize = config.fontSizes.speed
local gearFontSize = config.fontSizes.gear
local unitFontSize = config.fontSizes.unit

for i = 0, 3 do
    state.inputBarPositions[i + 1] = inputBarPos + vec2(inputBarSpacing * i, 0)
end

---@param percentage number
---@return rgbm
local function getRPMColor(percentage)
    if percentage >= 98 then return rpmColors[3].color end
    if percentage >= 94 then return rpmColors[2].color end
    return rpmColors[1].color
end

---@param pos vec2
---@param value number
---@param color rgbm
---@param invert? boolean
local function drawInputBar(pos, value, color, invert)
    local isFFB = color == config.colors.gray
    local height = isFFB and math.min(value, 1) or (invert and 1 - value or value)
    local barHeight = config.dimensions.inputBar.size.y * height
    if isFFB and value > 1 then color = config.colors.red end
    local cursor = state.center + pos
    ui.setCursor(cursor)
    ui.drawRectFilled(cursor, cursor + config.dimensions.inputBar.size, config.colors.halfBlack)
    ui.drawRectFilled(vec2(cursor.x, cursor.y + config.dimensions.inputBar.size.y - barHeight), cursor + vec2(config.dimensions.inputBar.size.x, config.dimensions.inputBar.size.y), color)
end

---@param isRight boolean
---@param dt any
---@param car ac.StateCar
local function updateIndicator(isRight, dt, car)
    local indicator = state.indicators[isRight and "right" or "left"]
    local isOn = isRight and car.turningRightLights or car.turningLeftLights
    local phaseDuration = state.indicators.phase.time or (config.indicator.animDuration + config.indicator.blinkDelay)
    if isOn and not indicator.active then indicator.progress, state.indicators.phase.accumulator = 0, 0 end
    indicator.active = isOn
    if (car.turningLightsActivePhase and isOn) or (indicator.progress > 0 and indicator.progress < 1) then
        indicator.progress = math.min(1, indicator.progress + dt / phaseDuration)
        if not state.indicators.phase.time and car.turningLightsActivePhase and isOn then
            state.indicators.phase.accumulator = state.indicators.phase.accumulator + dt
            if indicator.progress >= 1 then state.indicators.phase.time = state.indicators.phase.accumulator end
        end
        local width = config.dimensions.indicator.x * (config.indicator.minWidth + (2 - config.indicator.minWidth) * indicator.progress)
        local xPos = isRight and (state.center.x * 2 - config.dimensions.indicator.x) or (config.dimensions.indicator.x - width)
        ui.setCursor(vec2(xPos, 12))
        ui.drawRectFilled(ui.getCursor(), ui.getCursor() + vec2(width, config.dimensions.indicator.y), config.colors.yellow)
    elseif indicator.progress >= 1 then
        indicator.progress = 0
        if state.indicators.left.progress == 0 and state.indicators.right.progress == 0 then state.indicators.phase = { time = nil, accumulator = 0 } end
    end
end

---@param dt any
local function updateHighBeams(dt)
    local pressed = ac.isJoystickButtonPressed(0, 4)
    local fs = config.flashState

    if pressed and not state.prevHighBeamButton then
        if not state.highBeamToggled then
            state.highBeamToggled = true
            fs.elapsedTime = 0
            fs.originalHeadlightsState = ac.getCar(0).headlightsActive
        else
            state.highBeamToggled = false
            if not fs.originalHeadlightsState then ac.setHeadlights(false) end
            ac.setHighBeams(false)
        end
    end
    state.prevHighBeamButton = pressed

    if state.highBeamToggled then
        fs.elapsedTime = fs.elapsedTime + dt
        local cycle = fs.elapsedTime % 1
        fs.isBeamOn = cycle <= 0.15 or (cycle >= 0.2 and cycle < 0.3) or (cycle >= 0.35 and cycle < 0.45)
        if not fs.originalHeadlightsState then ac.setHeadlights(fs.isBeamOn) end
        ac.setHighBeams(fs.isBeamOn)
    end
end


local teleportsINI = ac.INIConfig.onlineExtras()

---@param groupName string
---@param positionName string
---@return number|nil
local function findTeleportPoint(groupName, positionName)
    if not teleportsINI then return end
    local index = 0

    for _, key in teleportsINI:iterateValues('TELEPORT_DESTINATIONS', 'POINT') do
        local suffix = key:match('_(%a+)$')
        if not suffix then
            local pointName = teleportsINI:get('TELEPORT_DESTINATIONS', key, '')
            if type(pointName) == 'table' then pointName = pointName[1] end

            local baseIndex = key:match('%d+')
            if baseIndex then
                local groupKey = 'POINT_' .. baseIndex .. '_GROUP'
                local group = teleportsINI:get('TELEPORT_DESTINATIONS', groupKey, '')
                if type(group) == 'table' then group = group[1] end

                if group == groupName and pointName == positionName then
                    return index
                end

                index = index + 1
            end
        end
    end

    return nil
end

local targetPoints = {
    findTeleportPoint("C1 Outer - Bayshore Access", "Position 1"),
    findTeleportPoint("C1 Outer - Bayshore Access", "Position 2")
}

---@param car ac.StateCar
local function teleportToC1Button(car)
    if ac.isJoystickButtonPressed(0, 2) and not state.tpButtonHeld then
        state.tpButtonHeld = true

        local function tryTeleport()
            for _, point in ipairs(targetPoints) do
                if point and ac.canTeleportToServerPoint(point) then
                    ac.teleportToServerPoint(point)
                    return
                end
            end
        end

        if not car.isInPitlane then
            ac.tryToTeleportToPits()
            setTimeout(tryTeleport, 1)
        else
            tryTeleport()
        end
    elseif not ac.isJoystickButtonPressed(0, 2) and state.tpButtonHeld then
        state.tpButtonHeld = false
    end
end



function script.windowMain(dt)
    local car = ac.getCar(0)
    if not car then return end
    if state.center.x == 0 then state.center = ui.availableSpace() * 0.5 end

    ui.setCursor(vec2(0, 22))
    ui.childWindow('main', config.dimensions.element, function()
        local cursorY, availX = ui.getCursor().y, ui.availableSpaceX()
        local rpmPercent = car.rpm / car.rpmLimiter
        local roundedRpmPercent = math.floor(rpmPercent * 100)

        if roundedRpmPercent ~= state.lastRpmPercent then
            state.rpmBarColor:set(getRPMColor(roundedRpmPercent))
            state.lastRpmPercent = roundedRpmPercent
        end

        ui.drawRectFilled(vec2(0, cursorY), vec2(availX, cursorY + config.dimensions.rpmBar.height), config.colors.halfBlack)
        ui.drawRectFilled(vec2(0, cursorY), vec2(availX * rpmPercent, cursorY + config.dimensions.rpmBar.height), state.rpmBarColor)

        local speed = math.floor(car.speedKmh + 0.5)
        if speed ~= state.lastSpeed then
            state.speedText = tostring(speed)
            state.lastSpeed = speed
        end

        ui.setCursor(state.center - config.dimensions.speed.number)
        ui.pushDWriteFont(config.fonts.bold)
        ui.dwriteTextAligned(state.speedText, speedFontSize, 1, 0, ui.measureDWriteText('999', speedFontSize), false, config.colors.white)
        ui.popDWriteFont()

        ui.setCursor(state.center - config.dimensions.speed.text)
        ui.pushDWriteFont(config.fonts.black)
        ui.dwriteTextAligned('KM/H', unitFontSize, -1, 0, ui.measureDWriteText('KM/H', speedFontSize), false, config.colors.white)
        ui.popDWriteFont()

        if car.gear ~= state.lastGear then
            state.gearText = car.gear == 0 and 'N' or car.gear == -1 and 'R' or tostring(car.gear)
            state.gearTextWidth = ui.measureDWriteText(state.gearText, gearFontSize)
            state.lastGear = car.gear
        end

        ui.setCursor(state.center - (state.gearTextWidth * 0.5) - vec2(0, 19))
        ui.pushDWriteFont(config.fonts.bold)
        ui.dwriteTextAligned(state.gearText, gearFontSize, 0, -1, state.gearTextWidth, false, config.colors.white)
        ui.popDWriteFont()

        drawInputBar(state.inputBarPositions[1], car.clutch, config.colors.aqua, true)
        drawInputBar(state.inputBarPositions[2], car.brake, config.colors.red)
        drawInputBar(state.inputBarPositions[3], car.gas, config.colors.lime)
        drawInputBar(state.inputBarPositions[4], math.abs(car.ffbFinal), config.colors.gray)

        if car.hasTurningLights then
            if car.turningLeftLights or state.indicators.left.progress > 0 then updateIndicator(false, dt, car) end
            if car.turningRightLights or state.indicators.right.progress > 0 then updateIndicator(true, dt, car) end
        end
    end)

    updateHighBeams(dt)
    teleportToC1Button(car)
end
