local meshNode, fumoNode, modelInserted
local meshOutline, fumoOutline
local meshShowOutline, fumoShowOutline = false, false
local meshPos, meshInitialPos = vec3(0, 0, 0), vec3(0, 0, 0)
local fumoPos, fumoInitialPos = vec3(0, 1, 0), vec3(0, 1, 0)
local targetMeshName = ''
local fileName
local speed = 0.05
local btnSize = vec2(60, 60)
local itemSpacing = 8

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

local function selectMesh()
    local node = ac.findNodes(targetMeshName)
    if not node:empty() then
        meshNode = node
        meshPos = meshNode:getPosition()
        meshInitialPos = meshPos:clone()
        meshOutline = ac.findMeshes(targetMeshName)
    end
end

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
        fumoNode = bodyNode:loadKN5('./LIDLFUMO.kn5')
        fumoPos = vec3(0, 1, 0)
        fumoNode:setPosition(fumoPos)
        fumoInitialPos = fumoPos:clone()
        fileName = getKN5Name()
        modelInserted = not fumoNode:empty()
        fumoOutline = ac.findMeshes('{LIDLFUMO?}')
    end
end

fumoNode = ac.findNodes('LIDLFUMO')
if not fumoNode:empty() then
    modelInserted = true
    fumoPos = fumoNode:getPosition()
    fumoInitialPos = fumoPos:clone()
    fileName = getKN5Name()
    fumoOutline = ac.findMeshes('{LIDLFUMO?}')
end

function script.windowMain(dt)
    ui.tabBar('moverTabs', function()
        ui.tabItem('Model Mover', function()
            ui.setNextItemWidth(ui.availableSpaceX())
            local nameChanged, enterPressed
            targetMeshName, nameChanged, enterPressed = ui.inputText('Enter Mesh Name...', targetMeshName, ui.InputTextFlags.Placeholder)
            if enterPressed then selectMesh() end
            if ui.button('Select Mesh', vec2(ui.availableSpaceX(), 0)) then selectMesh() end
            ui.separator()
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
                        meshPos[ctrl.axis] = meshPos[ctrl.axis] + ctrl.dir * currentSpeed * dt
                        moved = true
                    end
                end
                if ctrl.nl then
                    centerCursor(gridWidth)
                else
                    ui.sameLine()
                end
            end
            if moved and meshNode then meshNode:setPosition(meshPos) end
            ui.separator()
            centerCursor(225)
            ui.setNextItemWidth(225)
            speed = ui.slider('##Speed', speed, 0.001, 1, 'Speed: %.4f')
            local posText = string.format('Pos: %.6f, %.6f, %.6f', meshPos.x, meshPos.y, meshPos.z)
            centerCursor(ui.measureText(posText).x)
            ui.text(posText)
            local resetBtnWidth = ui.measureText('Reset X').x + 16
            centerCursor(resetBtnWidth * 3 + itemSpacing * 2)
            for i, axis in ipairs { 'x', 'y', 'z' } do
                if ui.button('Reset ' .. axis:upper()) then
                    meshPos[axis] = meshInitialPos[axis]
                    if meshNode then meshNode:setPosition(meshPos) end
                end
                if i < 3 then ui.sameLine() end
            end
            ui.separator()
            if ui.button('Toggle Outline') and meshOutline then
                meshShowOutline = not meshShowOutline
                meshOutline:setOutline(meshShowOutline and rgbm(0, 1, 1, 10) or nil)
            end
            ui.sameLine()
            centerCursor(ui.measureText('Copy Pos').x + 16)
            if ui.button('Copy Pos') then ac.setClipboardText(string.format('%.6f, %.6f, %.6f', meshPos.x, meshPos.y, meshPos.z)) end
        end)

        ui.tabItem('LIDL FUMO', function()
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
                        fumoPos[ctrl.axis] = fumoPos[ctrl.axis] + ctrl.dir * currentSpeed * dt
                        moved = true
                    end
                end
                if ctrl.nl then
                    centerCursor(gridWidth)
                else
                    ui.sameLine()
                end
            end
            if moved then fumoNode:setPosition(fumoPos) end
            ui.separator()
            centerCursor(225)
            ui.setNextItemWidth(225)
            speed = ui.slider('##Speed2', speed, 0.01, 3, 'Speed: %.3f')
            local posText = string.format('Current Position: %.3f, %.3f, %.3f', fumoPos.x, fumoPos.y, fumoPos.z)
            centerCursor(ui.measureText(posText).x)
            ui.text(posText)
            local resetBtnWidth = ui.measureText('Reset X').x + 16
            centerCursor(resetBtnWidth * 3 + itemSpacing * 2)
            for i, axis in ipairs { 'x', 'y', 'z' } do
                if ui.button('Reset ' .. axis:upper()) then
                    fumoPos[axis] = fumoInitialPos[axis]
                    fumoNode:setPosition(fumoPos)
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
            if ui.button('Toggle Outline') and fumoOutline then
                fumoShowOutline = not fumoShowOutline
                fumoOutline:setOutline(fumoShowOutline and rgbm(0, 1, 1, 10) or nil)
            end
            ui.sameLine()
            centerCursor(ui.measureText('Copy ext_config.ini').x + 16)
            if ui.button('Copy ext_config.ini') then
                ac.setClipboardText(string.format('[MODEL_REPLACEMENT_...]\nACTIVE = 1\nFILE = %s\nINSERT = LIDLFUMO.kn5\nINSERT_AFTER = COCKPIT_HR\nSCALE = 1,1,1\nOFFSET = %.3f, %.3f, %.3f\nROTATION = 0, 0, 0\n\n[WOBBLY_BIT_...]\nNAME = LIDLFUMO\nCONNECTED_TO = %.3f, %.3f, %.3f\nMAX_RANGE = 0.9\nDAMPENING_LAG = 1\nOFFSET_GAIN = 0\nG_GAIN = 1.5\nGRAVITY_GAIN = 1\nG_FILTER = 0.1\nDEFAULT_GRAVITY_INCLUDED_ALREADY = 0\nSTIFF_AXIS = 0,0,1\nSTIFF_AXIS_STIFFNESS = 0.7', fileName, fumoPos.x, fumoPos.y, fumoPos.z, fumoPos.x, fumoPos.y + 0.1, fumoPos.z))
            end
        end)
    end)
end
