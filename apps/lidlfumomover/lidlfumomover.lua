local modelNode, modelInserted
local meshOutline, showOutline = nil, false
local pos, initialPos = vec3(0, 1, 0), vec3(0, 1, 0)
local fileName
local speed = 0.3
local btnSize = vec2(60, 60)
local itemSpacing = 8

local function getKN5Name()
    local carID = ac.getCar(0):id()
    local carFolder = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID
    local kn5Files = io.scanDir(carFolder, '*.kn5')
    for _, file in ipairs(kn5Files) do
        if file:match('_lod_') then return file:match('(.+_lod_.+)%.kn5'):gsub('_lod_.+', '.kn5') end
    end
    for _, file in ipairs(kn5Files) do
        if not file:match('collider%.kn5') then return file end
    end
    return 'Cannot find car .kn5'
end

local function insertModelKN5()
    if ac.findNodes('LIDLFUMO'):empty() then
        local bodyNode = ac.findNodes('BODYTR')
        modelNode = bodyNode:loadKN5('./LIDLFUMO.kn5')
        pos = vec3(0, 1, 0)
        modelNode:setPosition(pos)
        initialPos = pos:clone()
        fileName = getKN5Name()
        modelInserted = not modelNode:empty()
        meshOutline = ac.findMeshes('{LIDLFUMO?}')
    end
end

modelNode = ac.findNodes('LIDLFUMO')
if not modelNode:empty() then
    modelInserted = true
    pos = modelNode:getPosition()
    initialPos = pos:clone()
    fileName = getKN5Name()
    meshOutline = ac.findMeshes('{LIDLFUMO?}')
end

local controls = {
    { name = 'UP', axis = 'y', dir = 1 },
    { name = 'FWD', axis = 'z', dir = 1 },
    { name = 'DOWN', axis = 'y', dir = -1, nl = true },
    { name = 'LEFT', axis = 'x', dir = 1 },
    { name = '', axis = '', dir = 0 },
    { name = 'RIGHT', axis = 'x', dir = -1, nl = true },
    { name = '', axis = '', dir = 0 },
    { name = 'BACK', axis = 'z', dir = -1, nl = true },
}

local function centerCursor(width) ui.offsetCursorX((ui.availableSpaceX() - width) * 0.5) end

function script.windowMain(dt)
    if not modelInserted then
        centerCursor(ui.measureText('Insert Model').x + 16)
        if ui.button('Insert Model') then insertModelKN5() end
        return
    end

    local currentSpeed = speed * (ui.keyboardButtonDown(ui.KeyIndex.Shift) and 0.5 or 1) * (ui.keyboardButtonDown(ui.KeyIndex.Control) and 2 or 1)
    local moved = false
    local gridWidth = btnSize.x * 3 + itemSpacing * 2

    centerCursor(gridWidth)
    for _, ctrl in ipairs(controls) do
        if ctrl.name == '' then
            ui.dummy(btnSize)
        else
            ui.button(ctrl.name, btnSize)
            if ui.itemActive() then
                pos[ctrl.axis] = pos[ctrl.axis] + ctrl.dir * currentSpeed * dt
                moved = true
            end
        end
        if ctrl.nl then
            centerCursor(gridWidth)
        else
            ui.sameLine()
        end
    end

    if moved then modelNode:setPosition(pos) end

    ui.separator()
    centerCursor(225)
    ui.setNextItemWidth(225)
    speed = ui.slider('##Speed', speed, 0.01, 3, 'Speed: %.3f')

    local posText = string.format('Current Position: %.3f, %.3f, %.3f', pos.x, pos.y, pos.z)
    centerCursor(ui.measureText(posText).x)
    ui.text(posText)

    local resetBtnWidth = ui.measureText('Reset X').x + 16
    centerCursor(resetBtnWidth * 3 + itemSpacing * 2)
    for i, axis in ipairs { 'x', 'y', 'z' } do
        if ui.button('Reset ' .. axis:upper()) then
            pos[axis] = initialPos[axis]
            modelNode:setPosition(pos)
        end
        if i < 3 then ui.sameLine() end
    end

    ui.separator()
    ui.offsetCursorY(4)
    centerCursor(ui.measureText('KN5:').x + itemSpacing + 184)
    ui.text('KN5:')
    ui.sameLine()
    ui.offsetCursorY(-4)
    ui.setNextItemWidth(184)
    fileName = ui.inputText('##file', fileName)

    if ui.button('Toggle Outline') and meshOutline then
        showOutline = not showOutline
        meshOutline:setOutline(showOutline and rgbm(0, 1, 1, 10) or nil)
    end

    ui.sameLine()
    centerCursor(ui.measureText('Copy ext_config.ini').x + 16)
    if ui.button('Copy ext_config.ini') then
        ac.setClipboardText(
            string.format(
                '[MODEL_REPLACEMENT_...]\nACTIVE = 1\nFILE = %s\nINSERT = LIDLFUMO.kn5\nINSERT_AFTER = COCKPIT_HR\nSCALE = 1,1,1\nOFFSET = %.3f, %.3f, %.3f\nROTATION = 0, 0, 0\n\n[WOBBLY_BIT_...]\nNAME = LIDLFUMO\nCONNECTED_TO = %.3f, %.3f, %.3f\nMAX_RANGE = 0.9\nDAMPENING_LAG = 1\nOFFSET_GAIN = 0\nG_GAIN = 1.5\nGRAVITY_GAIN = 1\nG_FILTER = 0.1\nDEFAULT_GRAVITY_INCLUDED_ALREADY = 0\nSTIFF_AXIS = 0,0,1\nSTIFF_AXIS_STIFFNESS = 0.7',
                fileName,
                pos.x,
                pos.y,
                pos.z,
                pos.x,
                pos.y + 0.1,
                pos.z
            )
        )
    end
end
