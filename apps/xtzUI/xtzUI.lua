local config = {
    dimensions = {
        element = vec2(297, 85),
        rpmBarHeight = 10,
        speed = { number = vec2(103, 49), text = vec2(78, 24) },
        inputBar = { position = vec2(51, -43), size = vec2(5, 54), spacing = 10 },
        indicator = vec2(55, 2),
        ping = { position = vec2(0, 18), offset = vec2(109, -12), bars = { count = 4, spacing = 5 } },
        steering = 3,
    },
    font = 'Reddit Mono:.\\src;Weight=Bold',
    fontSizes = { speed = 38, unit = 16, gear = 62, ping = 18 },
    colors = {
        rpm = {
            { level = 0,  color = rgbm.colors.white:clone() },
            { level = 94, color = rgbm.colors.yellow:clone() },
            { level = 98, color = rgbm.colors.red:clone() }
        },
        halfBlack = rgbm(0.15, 0.15, 0.15, 0.6),
        white = rgbm.colors.white:clone(),
        gray = rgbm.colors.gray:clone(),
        yellow = rgbm.colors.yellow:clone(),
        red = rgbm.colors.red:clone(),
        lime = rgbm.colors.lime:clone(),
        aqua = rgbm.colors.aqua:clone()
    },
    indicator = { minWidth = 0.2, animDuration = 0.1, blinkDelay = 0.15 },
    flashState = { isFlashing = false, elapsedTime = 0, currentFlash = 0, isBeamOn = false },
    joystick = {
        name = 'Thrustmaster TMX Racing Wheel',
        index = 0,
        detect = function(self)
            for i = 0, ac.getJoystickCount() - 1 do
                if ac.getJoystickName(i) == self.name then
                    self.index = i
                    return
                end
            end
        end
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
    highBeamToggled = false
}

local teleportsINI = ac.INIConfig.onlineExtras()

for i = 0, 4 do state.inputBarPositions[i + 1] = config.dimensions.inputBar.position + vec2(config.dimensions.inputBar.spacing * i, 0) end


---@param v vec2
---@return vec2
local function roundVec2(v)
    v.x = math.ceil(v.x)
    v.y = math.ceil(v.y)
    return v
end

---@param p number
---@return rgbm
local function getRPMColor(p)
    return p >= 98 and config.colors.rpm[3].color or (p >= 94 and config.colors.rpm[2].color or config.colors.rpm[1].color)
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

---@param pos vec2
---@param car ac.StateCar
local function drawSteeringBar(pos, car)
    local halfHeight = config.dimensions.steering / 2
    local normalized = math.lerpInvSat(car.steer, car.steerLock, -car.steerLock)
    local eased = normalized < 0.5 and 2 * normalized * normalized or 1 - 2 * (1 - normalized) * (1 - normalized)
    local steerLerp = math.lerp(halfHeight, config.dimensions.inputBar.size.y - halfHeight, eased)
    local cursor = state.center + pos

    ui.setCursor(cursor)
    ui.drawRectFilled(cursor, cursor + config.dimensions.inputBar.size, config.colors.halfBlack)
    ui.drawRectFilled(vec2(cursor.x, cursor.y + steerLerp - halfHeight), vec2(cursor.x + config.dimensions.inputBar.size.x, cursor.y + steerLerp + halfHeight), config.colors.white)
end

---@param isRight boolean
---@param dt any
---@param car ac.StateCar
local function updateIndicator(isRight, dt, car)
    local ind = state.indicators[isRight and 'right' or 'left']
    local on = isRight and car.turningRightLights or car.turningLeftLights
    local phaseDur = state.indicators.phase.time or (config.indicator.animDuration + config.indicator.blinkDelay)

    if on and not ind.active then ind.progress, state.indicators.phase.accumulator = 0, 0 end

    ind.active = on

    if (car.turningLightsActivePhase and on) or (ind.progress > 0 and ind.progress < 1) then
        ind.progress = math.min(1, ind.progress + dt / phaseDur)

        if not state.indicators.phase.time and car.turningLightsActivePhase and on then
            state.indicators.phase.accumulator = state.indicators.phase.accumulator + dt
            if ind.progress >= 1 then state.indicators.phase.time = state.indicators.phase.accumulator end
        end

        local width = config.dimensions.indicator.x * (config.indicator.minWidth + (2 - config.indicator.minWidth) * ind.progress)
        local x = isRight and (state.center.x * 2 - config.dimensions.indicator.x) or (config.dimensions.indicator.x - width)

        ui.setCursor(vec2(x, 12))
        ui.drawRectFilled(ui.getCursor(), ui.getCursor() + vec2(width, config.dimensions.indicator.y), config.colors.yellow)
    elseif ind.progress >= 1 then
        ind.progress = 0

        if state.indicators.left.progress == 0 and state.indicators.right.progress == 0 then state.indicators.phase = { time = nil, accumulator = 0 } end
    end
end

local function updateHighBeams(dt)
    local pressed = ac.isJoystickButtonPressed(config.joystick.index or 0, 4)
    local fs = config.flashState
    if pressed and not state.prevHighBeamButton then
        state.highBeamToggled = not state.highBeamToggled
        if state.highBeamToggled then
            fs.elapsedTime, fs.originalHeadlightsState = 0, ac.getCar(0).headlightsActive
        else
            if not fs.originalHeadlightsState then ac.setHeadlights(false) end
            ac.setHighBeams(false)
            ac.overrideCarControls(0).horn = false
        end
    end
    state.prevHighBeamButton = pressed
    if state.highBeamToggled then
        fs.elapsedTime = fs.elapsedTime + dt
        local c = fs.elapsedTime % 1
        fs.isBeamOn = c <= 0.15 or (c >= 0.2 and c < 0.3) or (c >= 0.35 and c < 0.45)
        if not fs.originalHeadlightsState then ac.setHeadlights(fs.isBeamOn) end
        ac.setHighBeams(fs.isBeamOn)
        ac.overrideCarControls(0).horn = fs.isBeamOn
    end
end


---@param group string
---@param posName string
---@return number|nil
local function findTeleportPoint(group, posName)
    if not teleportsINI then return end
    local idx = 0
    for _, key in teleportsINI:iterateValues('TELEPORT_DESTINATIONS', 'POINT') do
        if not key:match('_(%a+)$') then
            local name = teleportsINI:get('TELEPORT_DESTINATIONS', key, '')
            if type(name) == 'table' then name = name[1] end
            local base = key:match('%d+')
            if base then
                local groupKey = 'POINT_' .. base .. '_GROUP'
                local groupVal = teleportsINI:get('TELEPORT_DESTINATIONS', groupKey, '')
                if type(groupVal) == 'table' then groupVal = groupVal[1] end
                if groupVal == group and name == posName then return idx end
                idx = idx + 1
            end
        end
    end
end

local targetPoints = {
    findTeleportPoint('C1 Outer - Bayshore Access', 'Position 1'),
    findTeleportPoint('C1 Outer - Bayshore Access', 'Position 2')
}

---@param car ac.StateCar
local function teleportToC1Button(car)
    local pressed = ac.isJoystickButtonPressed(config.joystick.index or 0, 2)
    if pressed and not state.tpButtonHeld then
        state.tpButtonHeld = true
        local function tryTeleport()
            for _, p in ipairs(targetPoints) do
                if p and ac.canTeleportToServerPoint(p) then
                    ac.teleportToServerPoint(p)
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
    elseif not pressed and state.tpButtonHeld then
        state.tpButtonHeld = false
    end
end

config.joystick:detect()

function script.windowMain(dt)
    local car = ac.getCar(0)
    if not car then return end
    if state.center.x == 0 then state.center = ui.availableSpace() * 0.5 end

    ui.setCursor(vec2(0, 22))
    ui.childWindow('main', config.dimensions.element, function()
        local x, y = ui.availableSpaceX(), ui.getCursor().y
        local rpmPct = car.rpm / car.rpmLimiter
        local rpmRounded = math.floor(rpmPct * 100)

        if rpmRounded ~= state.lastRpmPercent then
            state.rpmBarColor:set(getRPMColor(rpmRounded))
            state.lastRpmPercent = rpmRounded
        end

        ui.drawRectFilled(vec2(0, y), vec2(x, y + config.dimensions.rpmBarHeight), config.colors.halfBlack)
        ui.drawRectFilled(vec2(0, y), vec2(x * rpmPct, y + config.dimensions.rpmBarHeight), state.rpmBarColor)

        local spd = math.floor(car.speedKmh + 0.5)
        if spd ~= state.lastSpeed then
            state.speedText = tostring(spd)
            state.lastSpeed = spd
        end

        ui.setCursor(roundVec2(state.center - config.dimensions.speed.number))
        ui.pushDWriteFont(config.font)
        ui.dwriteTextAligned(state.speedText, config.fontSizes.speed, 1, 0, ui.measureDWriteText('999', config.fontSizes.speed), false, config.colors.white)
        ui.popDWriteFont()
        ui.setCursor(roundVec2(state.center - config.dimensions.speed.text))
        ui.pushDWriteFont(config.font)
        ui.dwriteTextAligned('KM/H', config.fontSizes.unit, -1, 0, ui.measureDWriteText('KM/H', config.fontSizes.speed), false, config.colors.white)
        ui.popDWriteFont()

        if car.gear ~= state.lastGear then
            state.gearText = car.gear == 0 and 'N' or car.gear == -1 and 'R' or tostring(car.gear)
            state.gearTextWidth = ui.measureDWriteText(state.gearText, config.fontSizes.gear)
            state.lastGear = car.gear
        end

        ui.setCursor(roundVec2(state.center - state.gearTextWidth * 0.5 - vec2(0, 16)))
        ui.pushDWriteFont(config.font)
        ui.dwriteTextAligned(state.gearText, config.fontSizes.gear, 0, -1, state.gearTextWidth, false, config.colors.white)
        ui.popDWriteFont()

        ui.beginRotation()
        drawInputBar(state.inputBarPositions[1], car.clutch, config.colors.aqua, true)
        drawInputBar(state.inputBarPositions[2], car.brake, config.colors.red)
        drawInputBar(state.inputBarPositions[3], car.gas, config.colors.lime)
        drawSteeringBar(state.inputBarPositions[4], car)
        drawInputBar(state.inputBarPositions[5], math.abs(car.ffbFinal), config.colors.gray)
        ui.endRotation(0)

        if car.hasTurningLights then
            if car.turningLeftLights or state.indicators.left.progress > 0 then updateIndicator(false, dt, car) end
            if car.turningRightLights or state.indicators.right.progress > 0 then updateIndicator(true, dt, car) end
        end
    end)

    updateHighBeams(dt)
    teleportToC1Button(car)
end
