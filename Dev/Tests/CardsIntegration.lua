local PEER = "Participant-TestRealm"
local REMOTE_HOST = "Remote-ForeignRealm"
local REMOTE_SESSION = "remote-session.1"

return function(Games)
    local Cards = Games.Cards
    local Holdem = Cards.TexasHoldem
    local Store = Cards.Store
    local Protocol = Cards.Protocol
    local Codec = Holdem.Codec
    local assertions = 0

    local function Check(value, message)
        assertions = assertions + 1
        assert(value, message)
    end

    local function Same(actual, expected, message)
        Check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end

    local function Copy(source)
        local copy = {}
        for key, value in pairs(source) do
            copy[key] = value
        end
        return copy
    end

    local function Fields(...)
        local fields = {}
        for index = 1, select("#", ...) do
            fields[index] = select(index, ...)
        end
        return fields
    end

    local function Changed(fields, index, value)
        local changed = Copy(fields)
        changed[index] = value
        return changed
    end

    local function RewritePackedField(payload, targetIndex, replacement)
        local separator = assert(payload:find(":", 1, true))
        local count = assert(tonumber(payload:sub(1, separator - 1)))
        local cursor, fields = separator + 1, {}
        for index = 1, count do
            separator = assert(payload:find(":", cursor, true))
            local length = assert(tonumber(payload:sub(cursor, separator - 1)))
            cursor = separator + 1
            fields[index] = payload:sub(cursor, cursor + length - 1)
            cursor = cursor + length
        end
        fields[targetIndex] = replacement
        local pieces = { count .. ":" }
        for _, field in ipairs(fields) do
            pieces[#pieces + 1] = #field .. ":" .. field
        end
        return table.concat(pieces)
    end

    local function FindSeat(projection, seatNumber)
        for _, seat in ipairs(projection.seats) do
            if seat.seat == seatNumber then
                return seat
            end
        end
    end

    local function HasPrivateKey(value)
        if type(value) ~= "table" then
            return false
        end
        for key, child in pairs(value) do
            if key == "deck" or key == "order" or key == "burnCards" then
                return true
            end
            if HasPrivateKey(child) then
                return true
            end
        end
        return false
    end

    local function HostSettings(overrides)
        local settings = {
            buyIn = 1000,
            smallBlind = 5,
            bigBlind = 10,
            maxPlayers = 2,
            actionSeconds = 15,
            allowRebuys = true,
        }
        for key, value in pairs(overrides or {}) do
            settings[key] = value
        end
        return settings
    end

    local function Rules(overrides)
        local settings = HostSettings(overrides)
        return {
            version = 2,
            buyIn = settings.buyIn,
            smallBlind = settings.smallBlind,
            bigBlind = settings.bigBlind,
            maxPlayers = settings.maxPlayers,
            actionSeconds = settings.actionSeconds,
        }
    end

    local function Settlement(id, endedAt, players)
        return {
            id = id,
            variantId = Cards.VARIANT_ID,
            endedAt = endedAt or 1,
            players = players or {
                {
                    id = "player-1",
                    name = "Player One",
                    buyIn = 1000,
                    rebuy = 0,
                    finalStack = 1000,
                    net = 0,
                },
            },
        }
    end

    local normalized, reason = Store:Normalize(nil)
    Check(normalized ~= nil, "Cards storage supplies a valid default subtree: " .. tostring(reason))
    Same(normalized.schemaVersion, 4, "Cards storage starts at schema four")
    Same(normalized.selectedVariant, Cards.VARIANT_ID, "Texas Hold'em is the initial Cards variant")
    Same(normalized.hostSettings.currencyMode, nil, "new tables persist no currency-mode choice")
    Same(normalized.hostSettings.buyIn, 10000, "default buy-in remains deterministic")
    Same(normalized.hostSettings.smallBlind, 50, "default small blind remains deterministic")
    Same(normalized.hostSettings.bigBlind, 100, "default big blind remains deterministic")
    Same(normalized.hostSettings.maxPlayers, 8, "default table exposes all eight seats")
    Same(normalized.hostSettings.actionSeconds, 30, "default action timer is thirty seconds")
    Same(normalized.hostSettings.allowRebuys, true, "default table permits between-hand rebuys")
    Same(normalized.tableSettings.scale, 100, "default table scale is one hundred percent")
    Same(normalized.tableSettings.font, "", "default table font uses Blizzard")
    Same(normalized.tableSettings.x, 0.5, "default horizontal anchor starts at the screen midpoint")
    Same(normalized.tableSettings.y, 0.5, "default vertical anchor starts at the screen midpoint")
    Same(normalized.tableSettings.showHistory, true, "hand history is visible by default")
    Same(#normalized.settlements, 0, "new storage has no fabricated settlements")
    Same(normalized.nextSessionId, 1, "session IDs begin at one")
    Same(normalized.nextHandId, 1, "hand IDs begin at one")
    Same(Cards.Gold:Parse(string.rep("9", 400), Cards.BUY_IN_MAX), nil, "oversized Gold text rejects safely")
    for _, example in ipairs({
        { 0, "0" },
        { 999, "999" },
        { 1000, "1K" },
        { 1550, "1.55K" },
        { 1655, "1.66K" },
        { 10450, "10.45K" },
        { 99949, "99.95K" },
        { 99950, "99.95K" },
        { 100500, "100.5K" },
        { 999499, "999.5K" },
        { 999994, "999.99K" },
        { 999995, "1M" },
        { 1050000, "1.05M" },
        { 1655000, "1.66M" },
        { 9950000, "9.95M" },
        { 999995000, "1B" },
        { 999995000000, "1T" },
        { Cards.MAX_TOTAL_CHIPS, "8T" },
    }) do
        Same(Cards.Gold:FormatCompact(example[1]), example[2], "compact Gold rounds at stable display boundaries")
    end

    local supplied = {
        schemaVersion = 1,
        selectedVariant = Cards.VARIANT_ID,
        hostSettings = HostSettings({ currencyMode = "practice" }),
        tableSettings = { scale = 125, x = 0.25, y = 0.75, showHistory = false },
        settlements = { Settlement("saved-session") },
        nextSessionId = 7,
        nextHandId = 19,
    }
    supplied.settlements[1].currencyMode = "gold"
    supplied.settlements[1].players[1].funded = false
    supplied.settlements[1].players[1].paid = true
    normalized = assert(Store:Normalize(supplied))
    supplied.hostSettings.buyIn = 999999
    supplied.tableSettings.x = 1
    supplied.settlements[1].players[1].name = "Mutated"
    Same(normalized.hostSettings.buyIn, 1000, "normalization detaches host settings from SavedVariables input")
    Same(normalized.tableSettings.x, 0.25, "normalization detaches table settings from SavedVariables input")
    Same(normalized.tableSettings.font, "", "legacy table settings gain the Blizzard font default")
    Same(normalized.settlements[1].players[1].name, "Player One", "normalization detaches settlement rows")
    Same(normalized.schemaVersion, 4, "schema-one Cards data migrates to schema four")
    Same(normalized.hostSettings.currencyMode, nil, "legacy host currency mode is removed during migration")
    Same(normalized.settlements[1].currencyMode, nil, "legacy settlement currency mode is removed during migration")
    Same(normalized.settlements[1].players[1].funded, nil, "legacy funding state is removed during migration")
    Same(normalized.settlements[1].players[1].paid, nil, "legacy payout state is removed during migration")
    Same(normalized.nextSessionId, 7, "valid session counter survives normalization")
    Same(normalized.nextHandId, 19, "valid hand counter survives normalization")

    local schemaTwo = assert(Store:Normalize({
        schemaVersion = 2,
        hostSettings = HostSettings({ buyIn = 100000, smallBlind = 500, bigBlind = 1000 }),
    }))
    Same(schemaTwo.schemaVersion, 4, "schema-two Cards data migrates to schema four")
    Same(schemaTwo.hostSettings.buyIn, 100000, "valid legacy whole-number buy-in is retained without rescaling")
    Same(schemaTwo.hostSettings.smallBlind, 500, "valid legacy small blind is retained without rescaling")
    Same(schemaTwo.hostSettings.bigBlind, 1000, "valid legacy big blind is retained without rescaling")
    local invalidLegacy = assert(Store:Normalize({
        schemaVersion = 2,
        hostSettings = HostSettings({ buyIn = 999 }),
    }))
    Same(invalidLegacy.hostSettings.buyIn, 10000, "invalid legacy host setup falls back to the new buy-in")
    Same(invalidLegacy.hostSettings.smallBlind, 50, "invalid legacy host setup falls back to the new small blind")
    Same(invalidLegacy.hostSettings.bigBlind, 100, "invalid legacy host setup falls back to the doubled big blind")
    local schemaThree = assert(Store:Normalize({
        schemaVersion = 3,
        tableSettings = { scale = 115, font = "Cards {Serif}", x = 0.4, y = 0.6, showHistory = false },
    }))
    Same(schemaThree.schemaVersion, 4, "schema-three Cards data migrates to schema four")
    Same(schemaThree.tableSettings.font, "Cards {Serif}", "schema-three SharedMedia font survives migration")

    local invalidDatabases = {
        { value = false, error = "invalid_settings" },
        { value = { schemaVersion = 0 }, error = "invalid_database_version" },
        { value = { schemaVersion = 5 }, error = "unsupported_database_version" },
        { value = { selectedVariant = "unknown" }, error = "invalid_variant" },
        { value = { nextSessionId = 0 }, error = "invalid_settings" },
        { value = { nextHandId = 1.5 }, error = "invalid_settings" },
        { value = { hostSettings = HostSettings({ currencyMode = "silver" }) }, error = "invalid_currency_mode" },
        { value = { hostSettings = HostSettings({ smallBlind = 0 }) }, error = "invalid_small_blind" },
        { value = { hostSettings = HostSettings({ smallBlind = 26, bigBlind = 52 }) }, error = "invalid_small_blind" },
        { value = { hostSettings = HostSettings({ bigBlind = 5 }) }, error = "invalid_big_blind" },
        {
            value = { schemaVersion = 3, hostSettings = HostSettings({ buyIn = 999 }) },
            error = "invalid_buy_in",
        },
        { value = { hostSettings = HostSettings({ buyIn = 10000001 }) }, error = "invalid_buy_in" },
        { value = { hostSettings = HostSettings({ maxPlayers = 1 }) }, error = "invalid_max_players" },
        { value = { hostSettings = HostSettings({ maxPlayers = 9 }) }, error = "invalid_max_players" },
        { value = { hostSettings = HostSettings({ actionSeconds = 16 }) }, error = "invalid_action_seconds" },
        { value = { hostSettings = HostSettings({ allowRebuys = 1 }) }, error = "invalid_rebuys" },
        { value = { tableSettings = { scale = 71 } }, error = "invalid_table_scale" },
        { value = { tableSettings = { font = 1 } }, error = "invalid_table_font" },
        { value = { tableSettings = { font = "   " } }, error = "invalid_table_font" },
        { value = { tableSettings = { font = string.rep("f", 129) } }, error = "invalid_table_font" },
        { value = { tableSettings = { font = "bad|font" } }, error = "invalid_table_font" },
        { value = { tableSettings = { x = -0.1 } }, error = "invalid_table_settings" },
        { value = { tableSettings = { y = 1.1 } }, error = "invalid_table_settings" },
        { value = { tableSettings = { showHistory = "yes" } }, error = "invalid_table_settings" },
        {
            value = {
                settlements = {
                    Settlement("bad-net", 1, {
                        {
                            id = "player-1",
                            name = "Player One",
                            buyIn = 100,
                            rebuy = 25,
                            finalStack = 150,
                            net = 26,
                        },
                    }),
                },
            },
            error = "invalid_settlement",
        },
        {
            value = { settlements = { Settlement("duplicate"), Settlement("duplicate") } },
            error = "invalid_settlement",
        },
    }
    for _, fixture in ipairs(invalidDatabases) do
        local rejected, errorCode = Store:Normalize(fixture.value)
        Same(rejected, nil, "invalid Cards SavedVariables reject transactionally")
        Same(errorCode, fixture.error, "invalid Cards SavedVariables report the precise boundary")
    end

    local retained = {}
    for index = 1, 52 do
        retained[index] = Settlement("retained-" .. index, index)
    end
    normalized = assert(Store:Normalize({ settlements = retained }))
    Same(#normalized.settlements, 50, "normalization bounds retained completed sessions")
    Same(normalized.settlements[1].id, "retained-3", "settlement retention discards the oldest sessions first")
    Same(normalized.settlements[50].id, "retained-52", "settlement retention keeps the newest session")

    normalized = assert(Store:Normalize(nil))
    Store:Bind(normalized)
    local hostCopy = Store:GetHostSettings()
    hostCopy.buyIn = 1
    Same(Store:GetHostSettings().buyIn, 10000, "host-setting reads return defensive copies")
    local tableCopy = Store:GetTableSettings()
    tableCopy.scale = 70
    tableCopy.font = "Outside mutation"
    Same(Store:GetTableSettings().scale, 100, "table-setting reads return defensive copies")
    Same(Store:GetTableSettings().font, "", "font-setting reads return defensive copies")
    Check(Store:SaveHostSettings(HostSettings()), "valid host settings replace the bound copy")
    Same(Store:GetHostSettings().buyIn, 1000, "saved host settings are immediately readable")
    Check(Store:SaveTableSettings({ scale = 130 }), "partial table settings merge through validation")
    Same(Store:GetTableSettings().scale, 130, "partial table settings update the requested field")
    Same(Store:GetTableSettings().x, 0.5, "partial table settings preserve untouched fields")
    Check(Store:SaveTableSettings({ font = "Cards Test Font" }), "valid SharedMedia font names persist")
    Same(Store:GetTableSettings().font, "Cards Test Font", "saved table font is immediately readable")
    Check(Store:SaveTableSettings({ font = "Cards {Serif}" }), "SharedMedia punctuation survives validation")
    Same(Store:GetTableSettings().font, "Cards {Serif}", "font validation matches the SharedMedia boundary")
    Check(not Store:SaveTableSettings({ font = string.rep("f", 129) }), "oversized font names reject")
    Same(Store:GetTableSettings().font, "Cards {Serif}", "rejected font names do not mutate the bound data")
    Check(not Store:SaveTableSettings({ x = math.huge }), "non-finite table positions reject")
    Same(Store:GetTableSettings().x, 0.5, "rejected table settings do not mutate the bound data")

    local storedSettlement = Settlement("session-result", 20, {
        {
            id = "winner",
            name = "Winner",
            buyIn = 1000,
            rebuy = 500,
            finalStack = 2000,
            net = 500,
        },
        {
            id = "loser",
            name = "Loser",
            buyIn = 1000,
            rebuy = 0,
            finalStack = 500,
            net = -500,
        },
    })
    Check(Store:AddSettlement(storedSettlement), "a complete session result is retained")
    storedSettlement.players[1].name = "Changed outside"
    local settlementCopy = Store:GetSettlements()
    Same(settlementCopy[1].players[1].name, "Winner", "stored settlement input is detached")
    settlementCopy[1].players[1].name = "Changed copy"
    Same(Store:GetSettlements()[1].players[1].name, "Winner", "settlement reads are detached")
    Same(Store:GetSettlements()[1].players[1].net, 500, "settlement net is recomputed at the boundary")
    Same(Store.SetSettlementPaid, nil, "session results expose no manual payout mutation")
    local shownTab
    local show = Games.UI.Show
    Games.UI.Show = function(_, tab)
        shownTab = tab
    end
    Check(Cards.Commands:Handle("results"), "results command handles retained sessions")
    Same(shownTab, "results", "results command opens the existing Results page")
    Games.UI.Show = show
    Same(#Test.messages, 0, "results command emits no visible chat")
    Check(not Store:AddSettlement(Settlement("session-result")), "duplicate settlement identity rejects")
    Same(Store:NextSessionId(), 1, "session counter allocates its current value")
    Same(Store:NextSessionId(), 2, "session counter advances monotonically")
    Same(Store:NextHandId(), 1, "hand counter allocates independently")
    Same(Store:NextHandId(), 2, "hand counter advances independently")
    normalized = assert(Store:Normalize({ nextSessionId = Cards.MAX_CHIPS, nextHandId = Cards.MAX_CHIPS }))
    Store:Bind(normalized)
    Same(Store:NextSessionId(), nil, "session counter refuses unsafe rollover")
    Same(Store:NextHandId(), nil, "hand counter refuses unsafe rollover")
    Same(Store.db.nextSessionId, Cards.MAX_CHIPS, "exhausted session counter remains unchanged")
    Same(Store.db.nextHandId, Cards.MAX_CHIPS, "exhausted hand counter remains unchanged")

    local ledger = Cards.Ledger.New("session-ledger")
    Check(ledger:AddPlayer("one", "One", 1000), "session ledger accepts a player once")
    Check(not ledger:AddPlayer("one", "Duplicate", 1000), "session ledger rejects duplicate identity")
    Same(ledger:BuildSettlement(Cards.VARIANT_ID, 1), nil, "unfinished ledgers cannot settle")
    Check(ledger:RecordRebuy("one", 1000), "session ledger records a rebuy")
    Same(ledger:GetPlayers()[1].rebuy, 1000, "rebuy amount accumulates without funding state")
    Same(ledger:GetPlayers()[1].funded, nil, "session accounting owns no funding state")
    Same(ledger:GetPlayers()[1].paid, nil, "session accounting owns no payout state")
    Check(ledger:SetFinalStack("one", 2500), "session ledger accepts a final balance")
    local settlement = assert(ledger:BuildSettlement(Cards.VARIANT_ID, 2))
    Same(settlement.players[1].net, 500, "session result subtracts buy-in and rebuys from final balance")
    Same(settlement.currencyMode, nil, "session result owns no currency-mode field")
    settlement.players[1].name = "Detached"
    Same(ledger:GetPlayers()[1].name, "One", "built settlements do not expose ledger state")
    Check(not ledger:RecordRebuy("missing", 1000), "rebuy cannot target an unknown player")
    Check(not ledger:SetFinalStack("missing", 0), "final balance cannot target an unknown player")

    local protocolFixtures = {
        { Protocol.Join("request.1", "session.1"), "J" },
        { Protocol.Welcome("session.1", "request.1", "player.1"), "W" },
        { Protocol.Projection("session.1", 0, "payload"), "P" },
        { Protocol.Action("session.1", "request.1", 1, "raise", 100, 2), "A" },
        { Protocol.SitOut("session.1", "request.1", 2, true), "O" },
        { Protocol.Rebuy("session.1", "request.1", 3), "B" },
        { Protocol.Heartbeat("session.1", "request.1"), "T" },
        { Protocol.Leave("session.1", "request.1"), "L" },
        { Protocol.Acknowledge("session.1", "request.1", 4), "K" },
        { Protocol.Error("request.1", 4, "invalid_action"), "E" },
        { Protocol.Close("session.1"), "X" },
    }
    for _, fixture in ipairs(protocolFixtures) do
        local message = Protocol.Decode(fixture[1])
        Check(message ~= nil, "canonical " .. fixture[2] .. " protocol packet decodes")
        Same(message.code, fixture[2], "canonical protocol packet retains its code")
    end
    Same(Protocol.Decode(Protocol.Join("request.2")).advertisedSession, nil, "join permits no discovery session hint")
    Same(
        Protocol.Decode(Protocol.Action("session.1", "request.1", 5, "fold", nil, 2)).targetAmount,
        nil,
        "non-amount action omits its target"
    )
    Same(
        Protocol.Decode(Protocol.SitOut("session.1", "request.1", 6, false)).sittingOut,
        false,
        "sit-in survives the wire"
    )
    Same(
        Protocol.Decode(Protocol.Error("request.1", nil, "invalid_session")).sequence,
        nil,
        "join rejection needs no action sequence"
    )
    Same(
        Protocol.Decode(Protocol.Welcome("session.1", "request.1", "name:Pe\195\169r-Realm")).playerId,
        "name:Pe\195\169r-Realm",
        "welcome accepts namespaced UTF-8 participant identities"
    )

    local malformedProtocol = {
        {},
        { "?" },
        { "J", "request.1" },
        { "J", "request.1", "", "extra" },
        { "J", "bad request", "" },
        { "J", string.rep("x", 129), "" },
        { "W", "session.1", "request.1", "bad|player" },
        { "P", "session.1", "-1", "payload" },
        { "P", "session.1", "0", "" },
        { "P", "session.1", "0", string.rep("x", 4097) },
        { "A", "session.1", "request.1", "0", "fold", "", "2" },
        { "A", "session.1", "request.1", "1", "skip", "", "2" },
        { "A", "session.1", "request.1", "1", "raise", "-1", "2" },
        { "A", "session.1", "request.1", "1", "raise", tostring(Cards.MAX_TOTAL_CHIPS + 1), "2" },
        { "A", "session.1", "request.1", "1", "check", "" },
        { "A", "session.1", "request.1", "1", "check", "", "-1" },
        { "O", "session.1", "request.1", "1", "true" },
        { "K", "session.1", "request.1", "1.5" },
        { "E", "request.1", "", string.rep("x", 65) },
        { "X", "bad session" },
        { "J", 1, "" },
    }
    for _, fields in ipairs(malformedProtocol) do
        Same(Protocol.Decode(fields), nil, "malformed Cards protocol packet rejects")
    end

    local descriptor = Games.GameTypes:Get(Cards.id)
    Check(descriptor ~= nil, "Cards is registered as a top-level game type")
    Same(descriptor.id, "cards", "Cards descriptor uses the stable game-type ID")
    Same(descriptor.protocolVersion, 3, "Cards rejects clients without turn-bound actions")
    Same(descriptor.resultsTitle, Cards.L.RESULTS_TITLE, "Cards descriptor owns its results title")
    Same(descriptor.controller, Cards.Controller, "Cards descriptor owns its controller")
    Same(descriptor.session, Cards.Session, "Cards descriptor owns its session")
    Same(descriptor.storage, Cards.Store, "Cards descriptor owns its storage")
    Same(descriptor.advert, Cards.Advert, "Cards descriptor owns discovery projection")
    Same(descriptor.ui.hostPage, Cards.HostPage, "Cards descriptor owns host setup")
    Same(descriptor.ui.settingsPage, Cards.SettingsPage, "Cards descriptor owns appearance settings")
    Same(descriptor.ui.hud, Cards.Table, "Cards descriptor owns the table HUD")
    Same(descriptor.ui.resultsPage, Cards.ResultsPage, "Cards descriptor owns its settlement view")
    Same(Games.GameTypes:GetDefault().id, "quiz", "Quiz remains the default game type")
    local variant = Cards.Variants:Get(Cards.VARIANT_ID)
    Check(variant ~= nil, "Texas Hold'em is registered inside Cards")
    Same(variant.protocolVersion, 2, "Texas Hold'em declares its whole-Gold variant protocol")
    Same(variant.rules, Holdem.Rules, "variant descriptor owns normalized rules")
    Same(variant.model, Holdem.Model, "variant descriptor owns the state machine")
    local variants = Cards.Variants:GetAll()
    Same(#variants, 1, "Cards exposes one initial variant")
    Same(variants[1], variant, "variant listing returns the registered descriptor")
    Check(not Cards.Variants:Register(variant), "duplicate variant identity rejects")

    local model = assert(Holdem.Model.New(Rules(), {
        { seat = 1, id = "codec-one", name = "Codec One", stack = 1000 },
        { seat = 2, id = "codec-two", name = "Codec Two", stack = 1000 },
    }))
    Check(model:StartHand("codec-hand", 1, Cards.CardCatalog:GetAll(), Test.now), "codec fixture starts a real hand")
    local recipientProjection = model:GetProjection("codec-one")
    recipientProjection.currencyMode = "practice"
    recipientProjection.allowRebuys = true
    FindSeat(recipientProjection, 1).connected = true
    FindSeat(recipientProjection, 2).connected = false
    FindSeat(recipientProjection, 1).funded = false
    local spectatorProjection = model:GetProjection(nil)
    spectatorProjection.currencyMode = "practice"
    spectatorProjection.allowRebuys = true
    Check(not HasPrivateKey(recipientProjection), "recipient projection contains no deck or burns")
    Check(not HasPrivateKey(spectatorProjection), "spectator projection contains no deck or burns")
    Same(#FindSeat(recipientProjection, 1).holeCards, 2, "recipient projection includes only its own hole cards")
    Same(FindSeat(recipientProjection, 2).holeCards, nil, "recipient projection omits opponent hole cards")
    Same(FindSeat(spectatorProjection, 1).holeCards, nil, "spectator projection omits first player's hole cards")
    Same(FindSeat(spectatorProjection, 2).holeCards, nil, "spectator projection omits second player's hole cards")
    local payload, encodeError = Codec.EncodeProjection(recipientProjection, Test.now)
    Check(payload ~= nil, "recipient projection encodes: " .. tostring(encodeError))
    Check(#payload <= 4096, "projection payload fits the mode boundary")
    local canonicalPayload = payload
    local decoded, decodeError = Codec.DecodeProjection(payload, Test.now)
    Check(decoded ~= nil, "recipient projection decodes: " .. tostring(decodeError))
    Same(decoded.activityId, Cards.VARIANT_ID, "projection round-trip retains activity identity")
    Same(decoded.activityVersion, 2, "projection round-trip retains activity protocol")
    Same(decoded.state, "preflop", "projection round-trip retains hand state")
    Same(decoded.currencyMode, Cards.CURRENCY_MODE, "projection wire padding always normalizes to Gold")
    Same(decoded.revision, recipientProjection.revision, "projection round-trip retains model revision")
    Same(decoded.rules.buyIn, 1000, "projection round-trip retains buy-in")
    Same(decoded.rules.smallBlind, 5, "projection round-trip retains small blind")
    Same(decoded.rules.bigBlind, 10, "projection round-trip retains big blind")
    Same(
        decoded.actionDeadline,
        recipientProjection.actionDeadline,
        "projection round-trip retains remaining action time"
    )
    Same(#decoded.actions, 2, "projection round-trip retains blind history")
    Same(#FindSeat(decoded, 1).holeCards, 2, "wire projection retains recipient hole cards")
    Same(FindSeat(decoded, 2).holeCards, nil, "wire projection cannot acquire opponent hole cards")
    Same(FindSeat(decoded, 1).connected, true, "wire projection retains a connected seat")
    Same(FindSeat(decoded, 2).connected, false, "wire projection retains a disconnected seat")
    Same(FindSeat(decoded, 1).funded, true, "deprecated funding wire padding always normalizes to true")
    Check(not HasPrivateKey(decoded), "decoded projection cannot expose host-only card state")
    Same(
        Codec.DecodeProjection(RewritePackedField(canonicalPayload, 1, "1"), Test.now),
        nil,
        "whole-Gold decoder rejects the former projection schema"
    )
    Same(
        Codec.DecodeProjection(RewritePackedField(canonicalPayload, 3, "1"), Test.now),
        nil,
        "whole-Gold decoder rejects the former activity version"
    )
    local legacyPayload = RewritePackedField(canonicalPayload, 5, "practice")
    Same(
        assert(Codec.DecodeProjection(legacyPayload, Test.now)).currencyMode,
        Cards.CURRENCY_MODE,
        "decoder accepts legacy practice padding without restoring practice behavior"
    )
    Same(
        Codec.DecodeProjection(RewritePackedField(canonicalPayload, 5, "silver"), Test.now),
        nil,
        "decoder rejects unknown legacy currency padding"
    )
    local missingWagerMaximum = model:GetProjection("codec-one")
    missingWagerMaximum.legalActions.maxTarget = nil
    payload = assert(Codec.EncodeProjection(missingWagerMaximum, Test.now))
    Same(Codec.DecodeProjection(payload, Test.now), nil, "wire decoder rejects a wager without its maximum target")
    local invertedWagerRange = model:GetProjection("codec-one")
    invertedWagerRange.legalActions.maxTarget = invertedWagerRange.legalActions.minTarget - 1
    payload = assert(Codec.EncodeProjection(invertedWagerRange, Test.now))
    Same(Codec.DecodeProjection(payload, Test.now), nil, "wire decoder rejects an inverted legal wager range")

    local manyActions = model:GetProjection("codec-one")
    manyActions.currencyMode = "practice"
    manyActions.allowRebuys = true
    manyActions.actions = {}
    for index = 1, 20 do
        manyActions.actions[index] = {
            revision = index,
            street = "preflop",
            seat = index % 2 + 1,
            action = "check",
            paid = 0,
            automatic = false,
        }
    end
    payload = assert(Codec.EncodeProjection(manyActions, Test.now))
    decoded = assert(Codec.DecodeProjection(payload, Test.now))
    Same(#decoded.actions, 16, "wire history is bounded to sixteen recent actions")
    Same(decoded.actions[1].revision, 5, "bounded wire history retains the newest action window")
    Same(decoded.actions[16].revision, 20, "bounded wire history retains the latest action")

    local duplicateCard = model:GetProjection("codec-one")
    duplicateCard.currencyMode = "practice"
    duplicateCard.allowRebuys = true
    duplicateCard.board = { duplicateCard.seats[1].holeCards[1] }
    payload = assert(Codec.EncodeProjection(duplicateCard, Test.now))
    Same(Codec.DecodeProjection(payload, Test.now), nil, "wire decoder rejects duplicate public and private cards")
    local invalidIdentity = model:GetProjection("codec-one")
    invalidIdentity.currencyMode = "practice"
    invalidIdentity.allowRebuys = true
    invalidIdentity.seats[1].name = string.rep("x", 257)
    Same(Codec.EncodeProjection(invalidIdentity, Test.now), nil, "wire encoder rejects oversized identity fields")
    local invalidState = model:GetProjection("codec-one")
    invalidState.currencyMode = "practice"
    invalidState.allowRebuys = true
    invalidState.state = "dealing"
    Same(Codec.EncodeProjection(invalidState, Test.now), nil, "wire encoder rejects unknown states")
    Same(Codec.DecodeProjection(canonicalPayload .. "x", Test.now), nil, "wire decoder rejects trailing payload bytes")
    Same(
        Codec.DecodeProjection(canonicalPayload:sub(1, #canonicalPayload - 1), Test.now),
        nil,
        "wire decoder rejects truncated payloads"
    )
    Same(Codec.DecodeProjection(string.rep("x", 4097), Test.now), nil, "wire decoder rejects oversized payloads")
    Same(Codec.DecodeProjection({}, Test.now), nil, "wire decoder requires a string payload")
    Same(Codec.DecodeProjection(canonicalPayload, "now"), nil, "wire decoder requires a numeric local clock")

    local sent = {}
    local clearCount, advertiseCount, stopAdvertCount = 0, 0, 0
    Games.Comms = {
        Send = function(_, target, gameTypeId, fields, tag)
            sent[#sent + 1] = { target = target, gameTypeId = gameTypeId, fields = Copy(fields), tag = tag }
            return true
        end,
        Clear = function()
            clearCount = clearCount + 1
        end,
        IsTagBusy = function()
            return false
        end,
    }
    Games.Discovery = {
        Advertise = function()
            advertiseCount = advertiseCount + 1
        end,
        StopHost = function()
            stopAdvertCount = stopAdvertCount + 1
        end,
    }
    local app = { initialized = true, restricted = false, encounter = false, refreshes = 0, tickerRequests = 0 }
    function app:Report(reportReason)
        self.reported = reportReason
        return false, reportReason
    end
    function app:RefreshPresenters()
        self.refreshes = self.refreshes + 1
    end
    function app:EnsureTicker()
        self.tickerRequests = self.tickerRequests + 1
    end
    function app:IsRestricted()
        return self.restricted
    end
    function app:IsWaiting()
        return self.restricted or self.encounter
    end
    function app:GetWaitingReason()
        return self.encounter and Games.L.ENCOUNTER_WAITING or Games.L.NET_RESTRICTED
    end
    function app:SyncWaiting()
        local waiting, wasWaiting = self:IsWaiting(), self.waiting == true
        self.waiting = waiting
        Cards.Controller:OnWaitingChanged(waiting, wasWaiting, waiting and self:GetWaitingReason() or nil)
    end
    function app:SyncRestriction()
        Cards.Session:SetRestricted(self.restricted)
        self:SyncWaiting()
    end
    Games.Main = app
    Cards.Table = {
        Show = function(self)
            self.shown = (self.shown or 0) + 1
        end,
        Refresh = function(self)
            self.refreshes = (self.refreshes or 0) + 1
        end,
    }
    Cards.ResultsPage = {
        Invalidate = function(self)
            self.invalidations = (self.invalidations or 0) + 1
        end,
    }

    local function ResetSent()
        sent = {}
    end

    local function Messages(code)
        local messages = {}
        for _, message in ipairs(sent) do
            if message.fields[1] == code then
                messages[#messages + 1] = message
            end
        end
        return messages
    end

    local function Bind(settings)
        local database = assert(Store:Normalize({ hostSettings = settings }))
        Store:Bind(database)
        Cards.Session:Initialize()
        Cards.Controller:Initialize(app)
        Cards.Controller.game = nil
        Cards.Controller.variant = nil
        Cards.Controller.settings = nil
        Cards.Controller.hostId = nil
        Cards.Controller.ledger = nil
        Cards.Controller.connected = nil
        Cards.Controller.paused = false
        Cards.Controller.pausedAt = nil
        Cards.Controller.autoPaused = false
        Cards.Controller.notice = nil
        Cards.Controller.settlementSaved = false
        app.restricted, app.encounter, app.waiting = false, false, false
        ResetSent()
    end

    Bind(HostSettings())
    Check(Cards.Controller:Start(), "social host starts a real controller session")
    Check(Cards.Controller:IsRunning(), "social controller owns a live table")
    Same(Cards.Session:GetView().role, "host", "host view is projected through the shared session contract")
    Same(Cards.Controller.game.seats[1].sittingOut, false, "social host is seated immediately")
    local socialAdvert = Cards.Advert:GetHosted(Cards.Controller, Cards.Session)
    Check(socialAdvert ~= nil, "social tables may enter discovery")
    Same(socialAdvert.activityId, Cards.VARIANT_ID, "social advert identifies its activity")
    Same(socialAdvert.activityVersion, 2, "social advert identifies its activity protocol")
    Same(socialAdvert.playerCount, 1, "social advert reports the host seat")
    Same(socialAdvert.maxPlayers, 2, "social advert reports configured capacity")
    Same(socialAdvert.joinable, true, "between-hand social table is joinable")

    local socialSession = Cards.Session.hostSession
    ResetSent()
    Cards.Session:Receive(PEER, Protocol.Join("join.1", socialSession))
    local peer = Cards.Session.peers[PEER:lower()]
    Check(peer ~= nil, "host session accepts a valid social join")
    Same(peer.playerId, "name:" .. PEER:lower(), "host derives participant identity from the native sender")
    Same(Cards.Controller.game.seatsById[peer.playerId].sittingOut, false, "social join is immediately seated in")
    Same(Cards.Controller.ledger.players[peer.playerId].funded, nil, "social join creates no funding state")
    Same(#Messages("W"), 1, "accepted join receives one welcome")
    Same(
        Protocol.Decode(Messages("W")[1].fields).playerId,
        peer.playerId,
        "host-generated participant identity survives welcome decoding"
    )
    Check(#Messages("P") >= 1, "accepted join receives a private projection")
    local joinedProjectionMessage = assert(Protocol.Decode(Messages("P")[1].fields))
    local joinedProjection = assert(Codec.DecodeProjection(joinedProjectionMessage.payload, Test.now))
    Same(FindSeat(joinedProjection, 2).connected, true, "first joined-seat projection cannot flicker disconnected")
    ResetSent()
    Check(Cards.Session:SendProjection(peer), "host sends an unchanged projection snapshot")
    Check(Cards.Session:SendProjection(peer), "host can follow it with another unchanged snapshot")
    local projectionMessages = Messages("P")
    local firstProjectionMessage = assert(Protocol.Decode(projectionMessages[1].fields))
    local secondProjectionMessage = assert(Protocol.Decode(projectionMessages[2].fields))
    Check(
        secondProjectionMessage.revision > firstProjectionMessage.revision,
        "every host projection gets a monotonic wire revision"
    )
    local firstProjectedView = assert(Codec.DecodeProjection(firstProjectionMessage.payload, Test.now))
    local secondProjectedView = assert(Codec.DecodeProjection(secondProjectionMessage.payload, Test.now))
    Same(
        firstProjectedView.revision,
        secondProjectedView.revision,
        "unchanged snapshots retain their semantic game revision"
    )
    Same(
        secondProjectedView.revision,
        Cards.Controller.game.revision,
        "wire ordering never replaces the semantic game revision"
    )
    socialAdvert = Cards.Advert:GetHosted(Cards.Controller, Cards.Session)
    Same(socialAdvert.playerCount, 2, "social advert includes the joined peer")
    Same(socialAdvert.joinable, false, "full social table stops accepting joins")

    ResetSent()
    Check(Cards.Controller:StartHand(), "seated social players can start a hand")
    Same(Cards.Controller.game:GetState(), "preflop", "controller starts at preflop")
    socialAdvert = Cards.Advert:GetHosted(Cards.Controller, Cards.Session)
    Same(socialAdvert.phase, "open", "active social hand advertises its phase")
    Same(socialAdvert.joinable, false, "active social hand is not joinable")
    local hostProjection = Cards.Controller:GetProjection(Cards.Controller.hostId)
    local peerProjection = Cards.Controller:GetProjection(peer.playerId)
    Same(#FindSeat(hostProjection, 1).holeCards, 2, "host receives its own private hole cards")
    Same(FindSeat(hostProjection, 2).holeCards, nil, "host presentation omits peer hole cards")
    Same(FindSeat(peerProjection, 1).holeCards, nil, "peer projection omits host hole cards")
    Same(#FindSeat(peerProjection, 2).holeCards, 2, "peer projection receives its own hole cards")
    Same(peerProjection.legalActions, nil, "peer receives no actions while the host is acting")
    Check(Cards.Session:Act("call"), "host routes its local legal action through the controller")
    peerProjection = Cards.Controller:GetProjection(peer.playerId)
    Check(peerProjection.legalActions.check, "peer projection receives host-authoritative legal actions on its turn")

    local reconnectPlayerId = peer.playerId
    ResetSent()
    Cards.Session:Receive(PEER, Protocol.Join("join.2", socialSession))
    peer = Cards.Session.peers[PEER:lower()]
    Same(peer.playerId, reconnectPlayerId, "known participant can reconnect during an active hand")
    Same(#Messages("W"), 1, "active-hand reconnect receives a fresh welcome")
    Same(#Cards.Controller.game.seats, 2, "active-hand reconnect does not allocate a duplicate seat")

    local function ParticipantAction(sequence, action, target)
        return Protocol.Action(socialSession, peer.request, sequence, action, target, Cards.Controller.game.revision)
    end

    ResetSent()
    Cards.Session:Receive(PEER, ParticipantAction(1, "check"))
    Same(peer.lastSequence, 1, "accepted participant action advances its sequence")
    Same(#Messages("K"), 1, "accepted participant action is acknowledged")
    Same(Cards.Controller.game:GetState(), "flop", "accepted big-blind check advances to the flop")
    Same(Cards.Controller.game.hand.betting.actorSeat, 2, "peer acts first after the flop")
    local revisionBeforeDuplicate = Cards.Controller.game.revision
    ResetSent()
    Cards.Session:Receive(PEER, Protocol.Join(peer.request, socialSession))
    Same(Cards.Session.peers[PEER:lower()], peer, "repeated join preserves the active peer")
    Same(peer.lastSequence, 1, "repeated join preserves action deduplication")
    Cards.Session:Receive(PEER, ParticipantAction(1, "fold"))
    Same(Cards.Controller.game.revision, revisionBeforeDuplicate, "duplicate participant sequence is ignored")
    Same(#Messages("K"), 1, "duplicate accepted sequence repeats its acknowledgement")

    Cards.Session:Receive(PEER, ParticipantAction(2, "bet"))
    Same(peer.lastSequence, 2, "rejected participant action consumes its idempotency sequence")
    Same(Cards.Controller.game.revision, revisionBeforeDuplicate, "rejected participant action cannot mutate the game")
    Same(#Messages("E"), 1, "rejected participant action receives a precise error")
    Same(Messages("E")[1].fields[4], "invalid_bet", "rejected participant action reports model legality")
    ResetSent()
    Cards.Session:Receive(PEER, ParticipantAction(2, "check"))
    Same(Cards.Controller.game.revision, revisionBeforeDuplicate, "duplicate rejected sequence cannot change action")
    Same(#Messages("E"), 1, "duplicate rejected sequence repeats its original error")
    Same(Messages("E")[1].fields[4], "invalid_bet", "duplicate rejection preserves its original reason")
    ResetSent()
    Cards.Session:Receive(PEER, ParticipantAction(3, "check"))
    Same(peer.lastSequence, 3, "corrected action uses a fresh sequence")
    Same(#Messages("K"), 1, "corrected participant action is acknowledged")
    Same(Cards.Controller.game.hand.betting.actorSeat, 1, "action returns to the host")

    local deadline = Cards.Controller.game.hand.actionDeadline
    local revisionBeforePause = Cards.Controller.game.revision
    Check(Cards.Controller:Pause("paused_for_test", false), "host can pause an active hand")
    Test.now = Test.now + 5
    Cards.Controller:Tick(deadline + 100)
    Same(Cards.Controller.game.revision, revisionBeforePause, "paused controller never applies a timeout")
    Check(Cards.Controller:Resume(), "host can resume a paused hand")
    Same(Cards.Controller.game.hand.actionDeadline, deadline + 5, "resume restores the complete remaining turn time")
    Test.now = Cards.Controller.game.hand.actionDeadline
    Cards.Controller:Tick(Test.now)
    Check(Cards.Controller.game.revision > revisionBeforePause, "exact deadline applies the automatic action")
    Same(
        Cards.Controller.game.hand.actions[#Cards.Controller.game.hand.actions].automatic,
        true,
        "timeout action is marked automatic"
    )
    Same(Cards.Controller.game:GetState(), "turn", "automatic host check advances the completed flop")

    local deadlineBeforeRestriction = Cards.Controller.game.hand.actionDeadline
    app.restricted = true
    app:SyncRestriction()
    Same(Cards.Controller.paused, true, "restriction leaves the controller paused")
    Same(Cards.Controller.autoPaused, true, "restriction pause is identified as automatic")
    Test.now = Test.now + 3
    app.restricted = false
    app:SyncRestriction()
    Same(Cards.Controller.paused, false, "restriction recovery resumes the table")
    Same(
        Cards.Controller.game.hand.actionDeadline,
        deadlineBeforeRestriction + 3,
        "restriction pause extends the turn deadline"
    )

    local deadlineBeforeEncounter = Cards.Controller.game.hand.actionDeadline
    app.encounter = true
    app:SyncWaiting()
    Same(Cards.Controller.paused, true, "boss encounters pause Cards through the generic wait contract")
    Same(Cards.Controller.notice, Games.L.ENCOUNTER_WAITING, "Cards uses the dedicated boss waiting notice")
    Test.now = Test.now + 2
    app.restricted = true
    app:SyncRestriction()
    app.encounter = false
    app:SyncWaiting()
    Same(Cards.Controller.paused, true, "ending an encounter cannot resume through chat restriction")
    Same(Cards.Controller.notice, Games.L.NET_RESTRICTED, "the remaining blocker owns the waiting notice")
    app.restricted = false
    app:SyncRestriction()
    Same(Cards.Controller.paused, false, "Cards resumes after both automatic blockers clear")
    Same(
        Cards.Controller.game.hand.actionDeadline,
        deadlineBeforeEncounter + 2,
        "encounter waiting preserves the remaining action time"
    )

    app.encounter = true
    app:SyncWaiting()
    Check(Cards.Controller:Pause(nil, false), "manual pause can take ownership of an automatic Cards wait")
    Same(Cards.Controller.autoPaused, false, "manual Cards pause clears automatic ownership")
    app.encounter = false
    app:SyncWaiting()
    Same(Cards.Controller.paused, true, "encounter recovery cannot cancel a manual Cards pause")
    Check(Cards.Controller:Resume(), "manually owned Cards pause remains explicitly resumable")
    peer.lastSeen = Test.now - 100
    Cards.Session.nextSnapshot = Test.now + 100
    Cards.Session:Tick(Test.now)
    Same(Cards.Session.peers[PEER:lower()], nil, "host expires a silent active-hand peer")
    Same(
        Cards.Controller.game.seatsById[peer.playerId].sittingOut,
        false,
        "active-hand disconnect defers the sitting-out transition"
    )
    local actor = Cards.Controller.game.seats[Cards.Controller.game.hand.betting.actorSeat]
    Check(Cards.Controller:AcceptAction(actor.id, "fold"), "remaining actor can fold to complete the social hand")
    Same(Cards.Controller.game:GetState(), "complete", "social hand settles before session close")
    Same(
        Cards.Controller.game.seatsById[peer.playerId].sittingOut,
        true,
        "completed hand automatically sits out the disconnected peer"
    )
    local restarted, restartReason = Cards.Controller:StartHand()
    Same(restarted, false, "host cannot deal a disconnected ghost into the next hand")
    Same(restartReason, "not_enough_players", "ghost-seat prevention reports insufficient active players")
    Check(Cards.Controller:Stop(), "completed social session closes cleanly")
    Same(#Store:GetSettlements(), 1, "social session creates one durable settlement")
    Same(Store:GetSettlements()[1].currencyMode, nil, "social settlement stores no currency mode")
    Same(Cards.Advert:GetHosted(Cards.Controller, Cards.Session), nil, "closed social session leaves discovery")
    Check(
        clearCount > 0 and advertiseCount > 0 and stopAdvertCount > 0,
        "session lifecycle coordinates comms and discovery"
    )

    Bind(HostSettings({ currencyMode = "gold" }))
    Same(Store:GetHostSettings().currencyMode, nil, "legacy Gold host setting is normalized away before startup")
    Check(Cards.Controller:Start(), "legacy Gold settings start the unified social controller")
    Same(Cards.Controller.game.seats[1].sittingOut, false, "legacy Gold host is seated without funding")
    Check(Cards.Advert:GetHosted(Cards.Controller, Cards.Session) ~= nil, "legacy Gold settings do not hide discovery")
    local migratedSession = Cards.Session.hostSession
    Cards.Session:Receive(PEER, Protocol.Join("migrated-join.1", migratedSession))
    peer = Cards.Session.peers[PEER:lower()]
    Check(peer ~= nil, "participant may join a migrated social table")
    Same(Cards.Controller.game.seatsById[peer.playerId].sittingOut, false, "participant joins without funding")
    Same(Cards.Controller.ledger.players[peer.playerId].funded, nil, "controller ledger creates no funding marker")
    Same(Cards.Controller.MarkFunded, nil, "controller exposes no manual funding operation")
    Check(Cards.Controller:StartHand(), "two social seats can start a hand")
    Check(Cards.Advert:GetHosted(Cards.Controller, Cards.Session) ~= nil, "active social table remains discoverable")
    actor = Cards.Controller.game.seats[Cards.Controller.game.hand.betting.actorSeat]
    Check(Cards.Controller:AcceptAction(actor.id, "fold"), "migrated social hand settles through normal actions")
    Check(Cards.Controller:Stop(), "completed migrated session closes cleanly")
    Same(#Store:GetSettlements(), 1, "migrated session creates one durable settlement")
    Same(#Store:GetSettlements()[1].players, 2, "social settlement retains every participating seat")

    Cards.Session:Initialize()
    Cards.Controller.game = nil
    ResetSent()
    local joined, joinError = Cards.Session:JoinHost(REMOTE_HOST, REMOTE_SESSION, {
        activityId = "wrong_activity",
        activityVersion = Cards.ACTIVITY_VERSION,
        joinable = true,
    })
    Same(joined, false, "participant rejects a mismatched advertised activity")
    Same(joinError, "invalid_session", "mismatched advertised activity reports invalid session")
    joined, joinError = Cards.Session:JoinHost(REMOTE_HOST, REMOTE_SESSION, {
        activityId = Cards.VARIANT_ID,
        activityVersion = 1,
        joinable = true,
    })
    Same(joined, false, "participant rejects a former copper-denominated activity")
    Same(joinError, "invalid_session", "former activity protocol reports invalid session")
    joined, joinError = Cards.Session:JoinHost(REMOTE_HOST, REMOTE_SESSION, {
        activityId = Cards.VARIANT_ID,
        activityVersion = Cards.ACTIVITY_VERSION,
        joinable = false,
    })
    Same(joined, false, "participant rejects an advertised closed table")
    Same(joinError, "invalid_session", "closed advertised table reports invalid session")
    Check(
        Cards.Session:JoinHost(REMOTE_HOST, REMOTE_SESSION, {
            activityId = Cards.VARIANT_ID,
            activityVersion = Cards.ACTIVITY_VERSION,
            joinable = true,
        }),
        "participant can join a compatible advertised table"
    )
    Same(Cards.Session:GetView().state, "joining", "participant waits for host welcome")
    Same(#Messages("J"), 1, "participant sends exactly one initial join request")
    local client = Cards.Session.client
    Cards.Session:Receive(REMOTE_HOST, Protocol.Welcome(REMOTE_SESSION, client.request, "remote-player"))
    Same(Cards.Session:GetView().state, "waiting", "host welcome establishes participant membership")
    Same(client.session, REMOTE_SESSION, "participant retains the authoritative host session")
    Same(client.playerId, "remote-player", "participant retains its host-assigned identity")

    local remoteModel = assert(Holdem.Model.New(Rules(), {
        { seat = 1, id = "remote-player", name = "Local Participant", stack = 1000 },
        { seat = 2, id = "remote-host", name = "Remote Host", stack = 1000 },
    }))
    Check(
        remoteModel:StartHand("remote-hand", 1, Cards.CardCatalog:GetAll(), Test.now),
        "remote projection fixture starts"
    )
    local remoteProjection = remoteModel:GetProjection("remote-player")
    remoteProjection.currencyMode = "practice"
    remoteProjection.allowRebuys = true
    payload = assert(Codec.EncodeProjection(remoteProjection, Test.now))
    Cards.Session:Receive(REMOTE_HOST, Protocol.Projection(REMOTE_SESSION, remoteProjection.revision, payload))
    local clientView = Cards.Session:GetView()
    Same(clientView.state, "preflop", "participant accepts the host projection")
    Same(clientView.role, "participant", "accepted projection retains participant role")
    Same(clientView.hostName, REMOTE_HOST, "accepted projection retains selected host")
    Same(#FindSeat(clientView, 1).holeCards, 2, "participant wire view includes its own hole cards")
    Same(FindSeat(clientView, 2).holeCards, nil, "participant wire view omits host hole cards")
    Check(clientView.legalActions.call, "participant acts only from host-projected legal actions")
    Cards.Session:Receive(REMOTE_HOST, Protocol.Welcome(REMOTE_SESSION, client.request, "remote-player"))
    Same(Cards.Session:GetView(), clientView, "duplicate welcome preserves the accepted projection")
    Same(clientView.state, "preflop", "duplicate welcome cannot return a live table to waiting")

    ResetSent()
    Check(Cards.Session:Act("call"), "participant sends a legal-looking action request")
    Same(Cards.Session:GetView().pending, true, "participant waits for host acknowledgement")
    Same(#Messages("A"), 1, "participant action uses the Cards action packet")
    local pendingSequence = client.pendingSequence
    Cards.Session:OnSendError(REMOTE_HOST, "send_failed")
    Same(client.pendingSequence, pendingSequence, "unrelated transport failure cannot unlock a pending action")
    Same(Cards.Session:GetView().pending, true, "transport failure leaves the action retry active")
    Cards.Session:Tick(Test.now + 4)
    Same(#Messages("A"), 2, "unacknowledged participant action retries at the application layer")
    Same(Messages("A")[2].fields[4], tostring(pendingSequence), "action retry preserves its idempotency sequence")
    Same(Messages("A")[2].fields[5], "call", "action retry preserves its original action")
    Check(not Cards.Session:Act("fold"), "participant cannot overlap unconfirmed actions")
    Same(client.sequence, pendingSequence + 1, "attempted overlap still preserves monotonic request identity")
    Cards.Session:Receive(REMOTE_HOST, Protocol.Error(client.request, pendingSequence, "invalid_action"))
    Same(Cards.Session:GetView().pending, false, "host rejection clears participant pending state")
    Check(Cards.Session:GetView().notice ~= nil, "host rejection exposes an actionable notice")
    ResetSent()
    Check(Cards.Session:Act("call"), "participant can retry after a host rejection")
    local retrySequence = client.pendingSequence
    Check(retrySequence > pendingSequence, "participant retry uses a fresh monotonic sequence")
    Cards.Session:Receive(REMOTE_HOST, Protocol.Acknowledge(REMOTE_SESSION, client.request, retrySequence))
    Same(Cards.Session:GetView().pending, false, "matching acknowledgement clears participant pending state")
    Same(Cards.Session:GetView().notice, nil, "matching acknowledgement clears the prior rejection notice")

    local stableView = Cards.Session:GetView()
    local staleProjection = remoteModel:GetProjection("remote-player")
    staleProjection.currencyMode = "practice"
    staleProjection.allowRebuys = true
    staleProjection.revision = math.max(0, stableView.revision - 1)
    payload = assert(Codec.EncodeProjection(staleProjection, Test.now))
    Cards.Session:Receive(REMOTE_HOST, Protocol.Projection(REMOTE_SESSION, staleProjection.revision, payload))
    Same(Cards.Session:GetView(), stableView, "older host projection cannot rewind participant state")
    local duplicateProjection = remoteModel:GetProjection("remote-player")
    duplicateProjection.currencyMode = "practice"
    duplicateProjection.allowRebuys = true
    duplicateProjection.revision = stableView.revision
    payload = assert(Codec.EncodeProjection(duplicateProjection, Test.now))
    Cards.Session:Receive(REMOTE_HOST, Protocol.Projection(REMOTE_SESSION, duplicateProjection.revision, payload))
    Same(Cards.Session:GetView(), stableView, "equal host projection cannot rewind participant metadata")
    Cards.Session:SetRestricted(true)
    Same(Cards.Session:GetView().state, "paused", "messaging restriction overlays a paused participant view")
    local clientBeforeRestrictedTick = Cards.Session.client
    Cards.Session:Tick(Test.now + 100)
    Same(
        Cards.Session.client,
        clientBeforeRestrictedTick,
        "restricted tick cannot time out or reconnect the participant"
    )
    Cards.Session:SetRestricted(false)
    Same(Cards.Session:GetView().state, "preflop", "lifting restriction restores the last authoritative projection")

    Same(#Test.errors, 0, "Cards integration suite did not trigger the WoW error handler")
    return assertions
end
