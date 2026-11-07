-- Prueft die Logik des Companions gegen eine nachgebaute WoW-API. Ob das Spiel die API wirklich so anbietet, zeigt nur der Test im Spiel.
-- Aufruf aus dem Repo-Wurzelordner: lua tests/companion_test.lua
local ROOT = "ReforgeCompanion/"
local failures, checks = 0, 0

local function check(name, condition)
  checks = checks + 1
  if not condition then
    failures = failures + 1
    print("FEHLER: " .. name)
  end
end

-- Wie /combatlog: aendert den Zustand, ohne dass der Companion davon erfaehrt.
local function typeCommand(game, value)
  game.logging = value
end

-- Baut die Spielumgebung neu auf und laedt das Addon; `saved` sind die SavedVariables aus der letzten Sitzung.
local function newGame(opts)
  opts = opts or {}
  local game = {
    logging = opts.logging or false, now = 1000, inInstance = false, kind = "none", instanceId = 0,
    advanced = opts.advanced or "1", messages = {}, starts = 0, refuseStart = opts.refuseStart or false,
  }
  local eventFrame, ticker

  local function frame()
    local self = { scripts = {} }
    return setmetatable(self, { __index = function(_, name)
      if name == "SetScript" then
        return function(s, script, fn) s.scripts[script] = fn end
      end
      if name == "CreateTexture" or name == "CreateFontString" then
        return function()
          return setmetatable({}, { __index = function(_, method)
            if method == "SetText" then
              return function(s, text) s.text = text end
            end
            if method == "SetColorTexture" then
              return function(s, r, g, b) s.color = { r, g, b } end
            end
            return function() end
          end })
        end
      end
      if name == "GetPoint" then
        return function() return "TOP", nil, "TOP", 5, -5 end
      end
      if name == "SetShown" then
        return function(s, shown) s.shown = shown end
      end
      return function() end
    end })
  end

  local windows = {}
  CreateFrame = function(kind)
    local created = frame()
    if kind == "Frame" then
      eventFrame = created
    else
      windows[#windows + 1] = created
    end
    return created
  end
  GetLocale = function() return opts.locale or "deDE" end
  GetTime = function() return game.now end
  IsInInstance = function() return game.inInstance, game.kind end
  GetInstanceInfo = function() return "Name", game.kind, 0, "", 5, 0, false, game.instanceId end
  GetCVar = function() return game.advanced end
  SetCVar = function(_, value) game.advanced = value end
  -- Wie im Spiel: 5 Aufrufe in 10 Sekunden, auch reine Abfragen; im Limit geschieht nichts und die Antwort ist nil.
  game.calls, game.peak, game.limited, game.saturated = {}, 0, 0, false
  LoggingCombat = function(value)
    local recent = {}
    for _, at in ipairs(game.calls) do
      if game.now - at < 10 then recent[#recent + 1] = at end
    end
    game.calls = recent
    if game.saturated or #recent >= 5 then
      game.limited = game.limited + 1
      return nil
    end
    recent[#recent + 1] = game.now
    if #recent > game.peak then game.peak = #recent end
    if value == true and not game.refuseStart then
      if not game.logging then game.starts = game.starts + 1 end
      game.logging = true
    elseif value == false then
      game.logging = false
    end
    return game.logging
  end
  if opts.noApi then LoggingCombat = nil end
  C_Timer = { NewTicker = function(_, fn) ticker = fn end }
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) game.messages[#game.messages + 1] = text end }
  UIParent, GameTooltip = {}, setmetatable({}, { __index = function() return function() end end })
  SlashCmdList = {}
  ReforgeCompanionDB = opts.saved

  local ns = {}
  for _, file in ipairs({ "Core.lua", "UI.lua" }) do
    assert(loadfile(ROOT .. file))("ReforgeCompanion", ns)
  end

  function game.fire(event, ...) eventFrame.scripts.OnEvent(eventFrame, event, ...) end
  function game.login()
    game.fire("ADDON_LOADED", "Anderes")
    game.fire("ADDON_LOADED", "ReforgeCompanion")
    game.fire("PLAYER_LOGIN")
    game.fire("PLAYER_ENTERING_WORLD")
  end
  function game.enter(kind, id)
    game.inInstance, game.kind, game.instanceId = true, kind, id or 100
    game.fire("PLAYER_ENTERING_WORLD")
  end
  function game.leave()
    game.inInstance, game.kind, game.instanceId = false, "none", 0
    game.fire("PLAYER_ENTERING_WORLD")
  end
  function game.pass(seconds)
    game.now = game.now + seconds
    ticker()
  end
  game.ns, game.window = ns, function() return windows[1] end
  return game
end

-- Instanzen und Raids schalten ein, anderes nicht.
do
  local game = newGame()
  game.login()
  check("draussen kein Log", not game.logging)
  game.enter("raid")
  check("Raid startet das Log", game.logging)
  local dungeon = newGame()
  dungeon.login()
  dungeon.enter("party", 101)
  check("Instanz startet das Log", dungeon.logging)
  for _, kind in ipairs({ "arena", "pvp", "scenario" }) do
    local other = newGame()
    other.login()
    other.enter(kind)
    check(kind .. " startet kein Log", not other.logging)
  end
end

-- Kurz raus (Corpse-Run) darf das Log nicht zerteilen; erst nach der Frist stoppt es.
do
  local game = newGame()
  game.login()
  game.enter("raid")
  game.leave()
  check("beim Verlassen laeuft es weiter", game.logging)
  game.pass(200)
  check("innerhalb der Frist laeuft es weiter", game.logging)
  game.enter("raid")
  game.pass(200)
  game.leave()
  game.pass(299)
  check("Rueckkehr setzt die Frist zurueck", game.logging)
  check("Corpse-Run erzeugt keine neue Datei", game.starts == 1)
  game.pass(6)
  check("nach der Frist stoppt es", not game.logging)
end

-- Ein von Hand gestartetes Log bleibt Sache des Spielers.
do
  local game = newGame()
  game.login()
  game.ns.Toggle()
  check("von Hand gestartet", game.logging)
  game.enter("raid")
  game.leave()
  game.pass(11); game.pass(3600)
  check("von Hand gestartetes Log laeuft weiter", game.logging)

  local typed = newGame()
  typed.login()
  typeCommand(typed, true)
  typed.pass(11)
  typed.enter("raid"); typed.leave()
  typed.pass(11); typed.pass(3600)
  check("per /combatlog gestartetes Log laeuft weiter", typed.logging)
end

-- Wer es in der Instanz ausschaltet, dem schaltet es die Automatik nicht wieder an.
do
  local game = newGame()
  game.login()
  game.enter("raid", 7)
  game.ns.Toggle()
  game.pass(11)
  check("Ausschalten per Klick bleibt", not game.logging)
  check("Status zeigt die Sperre", game.ns.Status().suppressed)
  game.leave(); game.pass(11); game.enter("raid", 7)
  check("gilt auch nach dem Corpse-Run", not game.logging)
  game.leave(); game.pass(6); game.enter("raid", 8)
  check("die naechste Instanz loggt wieder", game.logging)

  local typed = newGame()
  typed.login()
  typed.enter("raid", 7)
  typeCommand(typed, false)
  typed.pass(11); typed.pass(11)
  check("Ausschalten per /combatlog bleibt", not typed.logging)
end

-- Automatik aus, und das Einschalten holt den Start nach.
do
  local game = newGame({ saved = { auto = false } })
  game.login()
  game.enter("raid")
  check("Automatik aus startet nichts", not game.logging)
  game.ns.SetAuto(true)
  check("Automatik an holt den Start nach", game.logging)
end

-- Advanced Logging wird vor dem Start gesetzt; ein fremd gestartetes Log ohne es wird angezeigt.
do
  local game = newGame({ advanced = "0" })
  game.login()
  check("ohne Start bleibt die Einstellung", game.advanced == "0")
  game.enter("raid")
  check("Start setzt Advanced Logging", game.advanced == "1")
  local typed = newGame({ advanced = "0" })
  typed.login()
  typeCommand(typed, true)
  typed.pass(11)
  check("Status meldet fehlendes Advanced Logging", typed.ns.Status().advanced == false)
end

-- /reload: Zuordnung bleibt; neuer Spielstart ohne laufendes Log: Zuordnung verfaellt.
do
  local game = newGame({ logging = true, saved = { startedByAddon = true } })
  game.login()
  game.pass(11); game.pass(300); game.pass(6)
  check("nach /reload beendet es sein eigenes Log", not game.logging)
  local fresh = newGame({ saved = { startedByAddon = true } })
  fresh.login()
  check("neuer Spielstart vergisst die Zuordnung", ReforgeCompanionDB.startedByAddon == false)
  local keep = newGame({ logging = true })
  keep.login()
  keep.pass(11); keep.pass(600)
  check("beim Laden laufendes fremdes Log bleibt", keep.logging)
end

-- Weigert sich das Spiel: genau eine Meldung statt einer je Sekunde.
do
  local game = newGame({ refuseStart = true })
  game.login()
  game.enter("raid")
  local count = #game.messages
  game.pass(6); game.pass(6); game.pass(6)
  check("Fehlschlag meldet sich einmal", #game.messages == count and count == 1)
end

-- Ohne die API laeuft alles weiter, ohne Lua-Fehler.
do
  local game = newGame({ noApi = true })
  game.login()
  game.enter("raid")
  game.pass(1)
  check("ohne API Zustand nicht verfuegbar", game.ns.Status().state == "unavailable")
  game.ns.Toggle()
end

-- Befehle und Anzeige.
do
  local game = newGame()
  game.login()
  local slash = SlashCmdList.REFORGECOMPANION
  slash("start"); check("/reforge start", game.logging)
  slash("start"); check("/reforge start ist kein Umschalter", game.logging and game.starts == 1)
  slash("stop"); check("/reforge stop", not game.logging)
  slash("auto"); check("/reforge auto", ReforgeCompanionDB.auto == false)
  slash("lock"); check("/reforge lock", ReforgeCompanionDB.locked == true)
  slash("hide"); check("/reforge hide", ReforgeCompanionDB.shown == false and game.window().shown == false)
  ReforgeCompanion_OnAddonCompartmentClick(); check("Addon-Menue blendet ein", ReforgeCompanionDB.shown == true)
  slash("hilfe")
  check("Fenster bekommt Klick", game.window().scripts.OnClick ~= nil)
  game.window().scripts.OnClick(game.window(), "LeftButton")
  check("Linksklick startet", game.logging)
  game.window().scripts.OnClick(game.window(), "RightButton")
  check("Rechtsklick schaltet die Automatik", ReforgeCompanionDB.auto == true)
end

-- Das Limit des Spiels: Der Companion bleibt deutlich darunter, damit andere Addons und /combatlog weiter funktionieren.
do
  local game = newGame()
  game.login()
  game.enter("raid")
  for _ = 1, 120 do game.pass(1) end
  check("hoechstens eine Abfrage je 10 Sekunden", #game.calls <= 2)
  check("im Betrieb nie im Limit", game.limited == 0 and game.peak <= 3)
end

-- Viele Zonenwechsel auf einmal kosten keine Aufrufe.
do
  local game = newGame()
  game.login()
  game.enter("raid")
  local before = #game.calls
  for _ = 1, 50 do game.fire("ZONE_CHANGED_NEW_AREA") end
  check("Ereignisse rufen die API nicht je Mal", #game.calls == before and game.limited == 0)
end

-- Im Limit heisst nil nicht "aus": keine Sperre, und das Log laeuft danach normal weiter.
do
  local game = newGame()
  game.login()
  game.enter("raid", 5)
  check("gestartet", game.logging)
  game.saturated = true
  for _ = 1, 30 do game.pass(1) end
  check("Limit zeigt das Log nicht als aus", game.ns.Status().state == "on")
  check("Limit setzt keine Sperre", not game.ns.Status().suppressed)
  check("Log laeuft wirklich weiter", game.logging and game.starts == 1)
  game.saturated = false
  game.leave()
  game.pass(1); game.pass(300); game.pass(6)
  check("eigenes Log wird danach trotzdem beendet", not game.logging)
end

-- Start im Limit: kein Fehler, sondern ein neuer Versuch.
do
  local game = newGame()
  game.login()
  game.saturated = true
  local before = #game.messages
  game.enter("raid", 5)
  check("im Limit noch nicht gestartet", not game.logging)
  check("im Limit keine Fehlermeldung", #game.messages == before)
  game.pass(2)
  game.saturated = false
  game.pass(6)
  check("Start wird nachgeholt", game.logging and game.starts == 1)
end

-- Stoppen im Limit wird nachgeholt.
do
  local game = newGame()
  game.login()
  game.enter("raid", 5)
  game.leave()
  game.pass(1)
  game.saturated = true
  game.pass(305)
  check("im Limit laeuft es noch", game.logging)
  game.saturated = false
  game.pass(6)
  check("Stopp wird nachgeholt", not game.logging)
end

-- Klick im Limit: Hinweis statt falschem Zustand.
do
  local game = newGame()
  game.login()
  game.saturated = true
  local before = #game.messages
  game.ns.Toggle()
  check("Klick im Limit aendert nichts", not game.logging and game.ns.Status().state == "off")
  check("Klick im Limit gibt einen Hinweis", #game.messages == before + 1 and game.messages[#game.messages]:find("begrenzt") ~= nil)
end

-- Laden im Limit: Die Zuordnung eines eigenen Logs bleibt, die naechste Abfrage klaert den Stand.
do
  local game = newGame({ logging = true, saved = { startedByAddon = true } })
  game.saturated = true
  game.login()
  check("Zuordnung bleibt, solange die Antwort unbekannt ist", ReforgeCompanionDB.startedByAddon == true)
  game.saturated = false
  game.pass(1); game.pass(301); game.pass(6)
  check("Eigenes Log wird danach beendet", not game.logging)
end

-- Beide Sprachen enthalten dieselben Texte.
do
  local de, en = newGame({ locale = "deDE" }).ns.L, newGame({ locale = "enUS" }).ns.L
  for field in pairs(de) do check("Englisch fehlt: " .. field, en[field] ~= nil) end
  for field in pairs(en) do check("Deutsch fehlt: " .. field, de[field] ~= nil) end
  check("fremde Sprache faellt auf Englisch", newGame({ locale = "frFR" }).ns.L.logOn == en.logOn)
end

print(("%d Pruefungen, %d Fehler"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
