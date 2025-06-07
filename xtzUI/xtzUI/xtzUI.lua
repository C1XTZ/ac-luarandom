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
        white = rgb.colors.white:clone(),
        gray = rgb.colors.gray:clone(),
        yellow = rgb.colors.yellow:clone(),
        red = rgb.colors.red:clone(),
        lime = rgb.colors.lime:clone(),
        aqua = rgb.colors.aqua:clone()
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
    indicators = { left = { progress = 0, active = false }, right = { progress = 0, active = false }, phase = { time = nil, accumulator = 0 } }
}

local function getRPMColor(percentage)
    local rpmColors = config.colors.rpm
    for i = #rpmColors, 1, -1 do
        if percentage >= rpmColors[i].level then return rpmColors[i].color end
    end
    return rpmColors[1].color
end

local function drawInputBar(pos, value, color, invert)
    local isFFB = color == config.colors.gray
    local height = isFFB and math.min(value, 1) or (invert and 1 - value or value)
    local barHeight = math.lerp(0, config.dimensions.inputBar.size.y, height)
    if isFFB and value > 1 then color = config.colors.red end
    local cursor = state.center + pos
    ui.setCursor(cursor)
    ui.drawRectFilled(cursor, cursor + config.dimensions.inputBar.size, config.colors.halfBlack)
    ui.drawRectFilled(vec2(cursor.x, cursor.y + config.dimensions.inputBar.size.y - barHeight), cursor + vec2(config.dimensions.inputBar.size.x, config.dimensions.inputBar.size.y), color)
end

local function updateIndicator(isRight, dt, car)
    local side, indicator = isRight and "right" or "left", state.indicators[isRight and "right" or "left"]
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

local function updateHighBeams(dt)
    local buttonPressed = ac.isJoystickButtonPressed(0, 4)
    local fs = config.flashState

    if buttonPressed then
        if not fs.isFlashing then
            fs.isFlashing = true
            fs.elapsedTime = 0
            fs.originalHeadlightsState = ac.getCar(0).headlightsActive
        end

        fs.elapsedTime = fs.elapsedTime + dt
        local cycle = fs.elapsedTime % 1
        fs.isBeamOn = cycle <= 0.1 or (cycle >= 0.15 and cycle < 0.25) or (cycle >= 0.3 and cycle < 0.35)

        if not fs.originalHeadlightsState then ac.setHeadlights(fs.isBeamOn) end
        ac.setHighBeams(fs.isBeamOn)
    else
        if fs.isFlashing and not fs.originalHeadlightsState then ac.setHeadlights(false) end
        fs.isFlashing = false
        fs.elapsedTime = 0
        ac.setHighBeams(false)
    end
end

function script.windowMain(dt)
    local car = ac.getCar(0)
    if state.center == vec2(0, 0) then state.center = ui.availableSpace():div(vec2(2, 2)) end

    ui.setCursor(vec2(0, 22))
    ui.childWindow('main', config.dimensions.element, function()
        local cursorY, availX = ui.getCursor().y, ui.availableSpaceX()
        local rpmPercent = car.rpm / car.rpmLimiter
        state.rpmBarColor:set(getRPMColor(math.round(rpmPercent * 100)))
        ui.drawRectFilled(vec2(0, cursorY), vec2(availX, cursorY + config.dimensions.rpmBar.height), config.colors.halfBlack)
        ui.drawRectFilled(vec2(0, cursorY), vec2(math.lerp(0, availX, rpmPercent), cursorY + config.dimensions.rpmBar.height), state.rpmBarColor)
        ui.setCursor(state.center - config.dimensions.speed.number)
        ui.pushDWriteFont(config.fonts.bold)
        ui.dwriteTextAligned(tostring(math.round(car.speedKmh)), config.fontSizes.speed, 1, 0, ui.measureDWriteText('999', config.fontSizes.speed), false, config.colors.white)
        ui.popDWriteFont()
        ui.setCursor(state.center - config.dimensions.speed.text)
        ui.pushDWriteFont(config.fonts.black)
        ui.dwriteTextAligned('KM/H', config.fontSizes.unit, -1, 0, ui.measureDWriteText('KM/H', config.fontSizes.speed), false, config.colors.white)
        ui.popDWriteFont()
        local gear = car.gear == 0 and 'N' or car.gear == -1 and 'R' or tostring(car.gear)
        local gearWidth = ui.measureDWriteText(gear, config.fontSizes.gear)
        ui.setCursor(state.center - (gearWidth / 2) - vec2(0, 19))
        ui.pushDWriteFont(config.fonts.bold)
        ui.dwriteTextAligned(gear, config.fontSizes.gear, 0, -1, gearWidth, false, config.colors.white)
        ui.popDWriteFont()
        drawInputBar(config.dimensions.inputBar.position, car.clutch, config.colors.aqua, true)
        drawInputBar(config.dimensions.inputBar.position + vec2(config.dimensions.inputBar.spacing, 0), car.brake, config.colors.red)
        drawInputBar(config.dimensions.inputBar.position + vec2(config.dimensions.inputBar.spacing * 2, 0), car.gas, config.colors.lime)
        drawInputBar(config.dimensions.inputBar.position + vec2(config.dimensions.inputBar.spacing * 3, 0), math.abs(car.ffbFinal), config.colors.gray)
        if car.hasTurningLights then
            if car.turningLeftLights or state.indicators.left.progress > 0 then updateIndicator(false, dt, car) end
            if car.turningRightLights or state.indicators.right.progress > 0 then updateIndicator(true, dt, car) end
        end
    end)

    updateHighBeams(dt)
end
