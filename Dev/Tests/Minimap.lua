local EPSILON = 0.000001
local DEFAULT_POSITION = 225
local FLAGS = { "hide", "lock", "showInCompartment" }
local ICON = "Interface\\AddOns\\Orbit-Games\\Assets\\Orbit.png"

return function(Games, development)
    local Quiz = Games.Quiz
    local assertions = 0
    local Store, QuizStore, Launcher, UI, Main = Games.Store, Quiz.Store, Games.Minimap, Games.UI, Games.Main
    local broker = LibStub("LibDataBroker-1.1")
    local icons = LibStub("LibDBIcon-1.0")
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end
    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
    local function Near(actual, expected, message)
        Check(math.abs(actual - expected) < EPSILON, message .. ": " .. actual .. " ~= " .. expected)
    end
    local function Copy(value)
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for key, child in pairs(value) do
            copy[key] = Copy(child)
        end
        return copy
    end
    local function Equal(actual, expected, message)
        if type(expected) ~= "table" then
            if type(expected) == "number" and expected ~= expected then
                Check(type(actual) == "number" and actual ~= actual, message .. " retains NaN input")
            else
                Same(actual, expected, message)
            end
            return
        end
        Same(type(actual), "table", message .. " remains a table")
        for key, value in pairs(expected) do
            Equal(actual[key], value, message .. "." .. tostring(key))
        end
        for key in pairs(actual) do
            Check(expected[key] ~= nil, message .. " adds no unexpected " .. tostring(key))
        end
    end
    local function BrokerCount()
        local count = 0
        for _ in broker:DataObjectIterator() do
            count = count + 1
        end
        return count
    end
    local function Initialize(saved)
        local db, reason = Store:Initialize(saved)
        Check(db ~= nil, "minimap preferences load: " .. tostring(reason))
        Same(db.schemaVersion, 1, "minimap preferences use the generic root schema")
        Same(db.modes.quiz.schemaVersion, 7, "root restoration retains the Quiz mode schema")
        return db
    end

    Same(Orbit, nil, "the minimap launcher works without Orbit")
    Same(Games.Development ~= nil, development, "the launcher loads in the requested source/release flavor")
    Same(Main.initialized, true, "successful application startup precedes launcher use")
    Same(Launcher.registered, true, "ADDON_LOADED registers the launcher automatically")
    Same(icons.loggedIn, true, "PLAYER_LOGIN reaches the real LibDBIcon positioning handler")
    Same(Games.Media.icon, ICON, "the launcher uses the standalone addon-list logo")
    Same(UI.frame, nil, "startup does not open or allocate the setup window")
    Same(Quiz.Widget.frame, nil, "startup does not allocate a quiz HUD")
    Same(BrokerCount(), 1, "startup creates one real broker object")
    Same(#icons:GetButtonList(), 1, "startup creates one real minimap button")
    local object = broker:GetDataObjectByName(Games.addonName)
    local button = icons:GetMinimapButton(Games.addonName)
    Check(object ~= nil and button ~= nil, "broker and icon share the addon registration name")
    Same(object.type, "launcher", "the broker advertises a launcher, not a data feed")
    Same(object.label, Games.L.W_TITLE, "broker label uses the application title")
    Same(object.icon, ICON, "broker exposes the bundled logo")
    Same(button.icon:GetTexture(), ICON, "LibDBIcon renders the broker's bundled logo")
    Same(button.dataObject, object, "the button retains the real broker proxy")
    Same(button:GetParent(), Minimap, "LibDBIcon owns native minimap parenting")
    Same(button:GetName(), "LibDBIcon10_Orbit-Games", "one library-owned frame identifies the addon")
    Same(button.clicks[1], "anyUp", "the real library registers all released mouse buttons")
    Same(button.drag, "LeftButton", "the real library registers normal left-button dragging")
    Same(button:IsShown(), true, "a new install shows the minimap icon")
    Same(button.db, Store:GetMinimapSettings(), "the library retains the live preference table")
    Same(button.db, OrbitGamesDB.minimap, "library drag writes reach SavedVariables directly")
    Same(button.db.minimapPos, DEFAULT_POSITION, "new icons begin at the stable default angle")
    Same(button.point[2], Minimap, "login positions the icon around the native minimap")
    Near(
        button.point[4],
        math.cos(math.rad(DEFAULT_POSITION)) * (Minimap:GetWidth() / 2 + icons.radius),
        "login applies the saved angle to horizontal position"
    )
    Near(
        button.point[5],
        math.sin(math.rad(DEFAULT_POSITION)) * (Minimap:GetHeight() / 2 + icons.radius),
        "login applies the saved angle to vertical position"
    )
    for _, key in ipairs(FLAGS) do
        Same(button.db[key], false, "optional library flag defaults to false: " .. key)
    end
    local frames, prefs = #Test.frames, button.db
    for _ = 1, 3 do
        Launcher:Initialize()
    end
    Same(#Test.frames, frames, "repeated initialization allocates no extra frames")
    Same(BrokerCount(), 1, "repeated initialization creates no extra broker objects")
    Same(icons:GetMinimapButton(Games.addonName), button, "repeated initialization retains the same icon")
    Same(button.db, prefs, "repeated initialization retains drag persistence")

    local nativeLibStub = LibStub
    for _, missing in ipairs({ "LibStub", "LibDataBroker-1.1", "LibDBIcon-1.0" }) do
        local uninitialized = {}
        if missing == "LibStub" then
            LibStub = nil
        else
            LibStub = function(name, silent)
                Same(silent, true, "optional minimap libraries are looked up silently")
                if name ~= missing then
                    return nativeLibStub(name, silent)
                end
            end
        end
        Launcher.Initialize(uninitialized)
        Same(uninitialized.registered, nil, "missing library leaves initialization retryable: " .. missing)
        Same(#Test.frames, frames, "missing libraries allocate no partial button")
        Same(BrokerCount(), 1, "missing libraries create no orphan broker object")
        LibStub = nativeLibStub
    end

    local beforeClicks, nativeCommand, commands = Copy(Store.db), Main.Command, {}
    Main.Command = function(self, command)
        commands[#commands + 1] = command
        return nativeCommand(self, command)
    end
    local function Click(mouseButton)
        button:GetScript("OnClick")(button, mouseButton)
    end
    Click("MiddleButton")
    Click("Button4")
    Same(#commands, 0, "unsupported mouse buttons issue no command")
    Same(UI.frame, nil, "unsupported mouse buttons leave setup unallocated")
    Click("LeftButton")
    Same(commands[1], "", "left click enters the normal command owner")
    Same(UI.frame:IsShown(), true, "left click opens setup")
    Same(UI.tab, "play", "ordinary opening retains the initial Games tab")
    Click("LeftButton")
    Same(UI.frame:IsShown(), false, "another left click closes setup")
    Click("RightButton")
    Same(commands[3], "settings", "right click enters the settings command")
    Same(UI.frame:IsShown(), true, "right click opens hidden setup")
    Same(UI.tab, "settings", "right click selects Settings")
    UI:SetTab("host")
    Click("RightButton")
    Same(UI.frame:IsShown(), true, "right click never toggles an already-open window closed")
    Same(UI.tab, "settings", "right click switches an open window from Host to Settings")
    Click("RightButton")
    Same(UI.frame:IsShown(), true, "repeated settings clicks keep the window open")
    local calls = #commands
    Click("MiddleButton")
    Click("UnknownButton")
    Same(#commands, calls, "unsupported buttons remain inert with an open window")
    Same(UI.tab, "settings", "unsupported buttons retain the active tab")
    UI.frame:Hide()
    Main.Command = nativeCommand
    Equal(Store.db, beforeClicks, "opening and closing setup do not modify saved preferences or scores")
    Same(Main:IsRunning(), false, "launcher clicks do not start gameplay")
    Same(Quiz.Session.hostSession, nil, "launcher clicks do not create a hosted session")
    Same(Quiz.Session.client, nil, "launcher clicks do not join a session")

    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:AddLine("Unrelated native tooltip")
    GameTooltip:Show()
    local nativeOwnerCalls = GameTooltip.ownerCalls
    local tooltip = icons.tooltip
    Same(tooltip, LibDBIconTooltip, "the real library owns its private tooltip")
    Check(tooltip ~= GameTooltip, "launcher hover never owns the shared native tooltip")
    button:GetScript("OnEnter")(button)
    Same(tooltip.owner, button, "LibDBIcon anchors its private tooltip to the button")
    Same(tooltip.ownerAnchor, "ANCHOR_NONE", "native library anchoring is retained")
    Same(tooltip:IsShown(), true, "hover shows the private tooltip")
    Same(tooltip:NumLines(), 4, "tooltip contains the title and three interaction hints")
    for index, text in ipairs({
        Games.L.W_TITLE,
        Games.L.W_MINIMAP_TOGGLE,
        Games.L.W_MINIMAP_SETTINGS,
        Games.L.W_MINIMAP_DRAG,
    }) do
        Same(tooltip.lines[index][1], text, "tooltip line uses the localized interaction text")
    end
    button:GetScript("OnLeave")(button)
    Same(tooltip:IsShown(), false, "leaving closes only the private tooltip")
    Same(GameTooltip.ownerCalls, nativeOwnerCalls, "hover never takes global tooltip ownership")
    Same(GameTooltip.owner, UIParent, "the global tooltip retains its unrelated owner")
    Same(GameTooltip:IsShown(), true, "leaving never hides another UI's tooltip")
    Same(GameTooltip:NumLines(), 1, "hover adds no lines to the global tooltip")
    Same(GameTooltip.lines[1][1], "Unrelated native tooltip", "global tooltip content is untouched")

    local beforeDrag, identities = Copy(Store.db), {}
    for key, value in pairs(Store.db) do
        identities[key] = value
    end
    button:GetScript("OnEnter")(button)
    button:GetScript("OnDragStart")(button)
    Same(tooltip:IsShown(), false, "drag start hides the private hover tooltip")
    Same(button.highlightLocked, true, "native drag feedback locks the icon highlight")
    Check(button:GetScript("OnUpdate") ~= nil, "dragging installs the real library position handler")
    button:GetScript("OnEnter")(button)
    Same(tooltip:IsShown(), false, "hover is suppressed during an active drag")
    Minimap:SetScale(0.8)
    local centerX, centerY = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    for _, point in ipairs({ { 1, 0, 0 }, { 0, 1, 90 }, { -1, 0, 180 }, { 0, -1, 270 }, { 1, -1, 315 } }) do
        Test.cursorX, Test.cursorY = (centerX + point[1] * 100) * scale, (centerY + point[2] * 100) * scale
        button:GetScript("OnUpdate")(button, 0)
        Near(prefs.minimapPos, point[3], "native dragging persists a normalized angle at nondefault scale")
        Same(Store:GetMinimapSettings(), prefs, "dragging retains the library's saved table identity")
        Near(
            button.point[4],
            math.cos(math.rad(point[3])) * (Minimap:GetWidth() / 2 + icons.radius),
            "dragging applies the saved angle to icon position"
        )
    end
    button:GetScript("OnDragStop")(button)
    Same(button:GetScript("OnUpdate"), nil, "drag end removes the per-frame position handler")
    Same(button.highlightLocked, false, "drag end unlocks native highlight feedback")
    Same(button.isMouseDown, false, "drag end releases the icon's pressed state")
    for key, value in pairs(beforeDrag) do
        if key ~= "minimap" then
            Same(Store.db[key], identities[key], "dragging retains unrelated field identity: " .. key)
            Equal(Store.db[key], value, "dragging cannot modify unrelated saved data: " .. key)
        end
    end
    Minimap:SetScale(1)
    Test.cursorX, Test.cursorY = 0, 0
    GameTooltip:Hide()

    Check(QuizStore:SaveSettings({ packId = "all", minimap = {} }), "Quiz setup still saves independently")
    Check(QuizStore:SaveWidgetSettings({ scale = 125, minimap = {} }), "widget appearance still saves independently")
    Check(QuizStore:SaveWidgetPosition(0.31, 0.69), "widget positioning still saves independently")
    Check(QuizStore:SaveSoundsEnabled(false), "sound preference still saves independently")
    Same(Store:GetMinimapSettings(), prefs, "other settings owners never replace the library-owned subtree")
    Near(prefs.minimapPos, 315, "other settings owners retain the dragged angle")
    Same(QuizStore:GetSettings().minimap, nil, "minimap preferences are not Quiz setup")
    Same(QuizStore:GetWidgetSettings().minimap, nil, "minimap preferences are not widget appearance")
    local dragged = Copy(Store.db)
    local supplied = Copy(dragged)
    supplied.minimap.minimapPos = supplied.minimap.minimapPos + 720
    local suppliedBefore = Copy(supplied)
    Equal(Initialize(supplied), dragged, "reload normalizes the dragged angle without altering any other saved data")
    Equal(supplied, suppliedBefore, "reload normalization never edits its input")

    Same(Initialize(nil).minimap.minimapPos, DEFAULT_POSITION, "a fresh database receives minimap defaults")
    Same(Initialize({}).minimap.minimapPos, DEFAULT_POSITION, "an empty restored database receives minimap defaults")
    local saved = { schemaVersion = 1 }
    local fresh = Initialize(saved)
    Same(fresh.minimap.minimapPos, DEFAULT_POSITION, "current root schema receives the default angle")
    Same(saved.minimap, nil, "defaulting does not mutate the caller's database")
    for _, key in ipairs(FLAGS) do
        Same(fresh.minimap[key], false, "defaults retain an ordinary visible draggable icon")
    end
    for _, angle in ipairs({ -45.5, 0, 360, 720.25 }) do
        saved.minimap = { minimapPos = angle, hide = true, lock = true, showInCompartment = true }
        local normalized = Initialize(saved)
        Near(normalized.minimap.minimapPos, angle % 360, "root restoration normalizes finite fractional angles")
        Check(normalized.minimap ~= saved.minimap, "restoration copies the supplied minimap table")
        Same(Store:GetMinimapSettings(), normalized.minimap, "the getter returns only the committed root subtree")
        Same(saved.minimap.minimapPos, angle, "normalization preserves the original angle input")
        for _, key in ipairs(FLAGS) do
            Same(normalized.minimap[key], true, "optional true flags survive root restoration")
        end
    end
    local db = Initialize(dragged)
    local personal = Quiz.PersonalScores.data
    local invalid = { false, true, 0, "bad" }
    for _, value in ipairs({ false, true, "225", {}, math.huge, -math.huge, 0 / 0 }) do
        invalid[#invalid + 1] = { minimapPos = value }
    end
    for _, key in ipairs(FLAGS) do
        for _, value in ipairs({ 0, 1, "false", {} }) do
            invalid[#invalid + 1] = { [key] = value }
        end
    end
    for _, value in ipairs(invalid) do
        local invalidSaved = { schemaVersion = 1, minimap = value }
        local before = Copy(invalidSaved)
        local loaded, reason = Store:Initialize(invalidSaved)
        Same(loaded, nil, "malformed minimap preferences reject atomically")
        Same(reason, "invalid_minimap_settings", "malformed minimap data reports the stable error")
        Same(Store.db, db, "failed restoration retains the previously committed database")
        Same(Quiz.PersonalScores.data, personal, "failed restoration retains personal-score ownership")
        Equal(invalidSaved, before, "failed restoration leaves supplied preferences untouched")
    end
    OrbitGamesDB = db
    Equal(db, dragged, "rejected preferences cannot corrupt the saved drag position or other settings")
    Same(#Test.errors, 0, "minimap startup and interaction produce no captured runtime errors")
    return assertions
end
