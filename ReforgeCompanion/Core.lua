-- Logik des Companions: entscheidet, wann das Kampflog laeuft. Die Anzeige liegt in UI.lua.
local _, ns = ...

-- Jeder Start des Logs erzeugt eine neue Datei. Wer stirbt und zuruecklaeuft, verlaesst kurz die Instanz:
-- darum stoppt das Log erst nach dieser Zeit ausserhalb, sonst zerfiele ein Raid in viele Dateien.
ns.STOP_GRACE = 300

local DEFAULTS = { auto = true, shown = true, locked = false }

local LOCALES = {
  enUS = {
    logOn = "Log running", logOff = "Log off", unavailable = "Log unavailable",
    party = "Dungeon", raid = "Raid", autoOn = "Auto: on", autoOff = "Auto: off", stopsIn = "Stops in %s",
    manualOff = "Turned off here", noAdvanced = "without Advanced Logging",
    started = "Combat log started (%s).", stopped = "Combat log stopped.",
    manualStarted = "Combat log started by hand. It keeps running until you stop it.",
    failed = "The game did not start the combat log.", busy = "The game is limiting combat log calls right now. Try again in a few seconds.", missingApi = "This game client offers no combat log function.",
    tipClick = "Left click: start or stop the log", tipRight = "Right click: automatic on or off", tipDrag = "Drag: move",
    tipAuto = "Automatic: logs in dungeons and raids, stops %d minutes after leaving.",
    help = "/reforge start | stop | auto | lock | show | hide | reset",
    position = "Window position reset.", locked = "Window locked.", unlocked = "Window unlocked.",
    hidden = "Window hidden. /reforge show brings it back.",
  },
  deDE = {
    logOn = "Log läuft", logOff = "Log aus", unavailable = "Log nicht verfügbar",
    party = "Instanz", raid = "Raid", autoOn = "Auto: an", autoOff = "Auto: aus", stopsIn = "Stoppt in %s",
    manualOff = "Hier ausgeschaltet", noAdvanced = "ohne Advanced Logging",
    started = "Kampflog gestartet (%s).", stopped = "Kampflog gestoppt.",
    manualStarted = "Kampflog von Hand gestartet. Es läuft, bis du es stoppst.",
    failed = "Das Spiel hat das Kampflog nicht gestartet.", busy = "Das Spiel begrenzt gerade Kampflog-Aufrufe. Versuche es in ein paar Sekunden noch einmal.", missingApi = "Dieser Spielclient bietet keine Kampflog-Funktion.",
    tipClick = "Linksklick: Log starten oder stoppen", tipRight = "Rechtsklick: Automatik an oder aus", tipDrag = "Ziehen: verschieben",
    tipAuto = "Automatik: loggt in Instanzen und Raids, stoppt %d Minuten nach dem Verlassen.",
    help = "/reforge start | stop | auto | lock | show | hide | reset",
    position = "Fensterposition zurückgesetzt.", locked = "Fenster fixiert.", unlocked = "Fenster gelöst.",
    hidden = "Fenster ausgeblendet. /reforge show holt es zurück.",
  },
}
ns.L = LOCALES[GetLocale()] or LOCALES.enUS
local L = ns.L

local db
-- Letzter bekannter Zustand. Das Spiel begrenzt LoggingCombat auf 5 Aufrufe in 10 Sekunden, geteilt mit allen Addons und /combatlog,
-- auch fuer reine Abfragen. Darum wird selten gefragt und sonst dieser Wert genutzt.
local logging = false
local nextQuery, nextAttempt = 0, 0
local loggingSince, stopAt, suppressedFor, failedFor

ns.QUERY_INTERVAL = 10
ns.ATTEMPT_INTERVAL = 5

function ns.Print(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cfff27a2creforge:|r " .. text)
end

local function apiAvailable()
  return type(LoggingCombat) == "function"
end

-- Instanztyp, wenn hier geloggt werden soll: nur Instanzen und Raids, nicht Arena, Schlachtfeld oder Szenario.
local function loggedInstance()
  local inInstance, kind = IsInInstance()
  if inInstance and (kind == "party" or kind == "raid") then
    return kind, select(8, GetInstanceInfo())
  end
  return nil, nil
end

local function advancedOn()
  return GetCVar("advancedCombatLogging") == "1"
end

-- Schaltet das Log. Rueckgabe: true = wie gewuenscht, false = das Spiel weigert sich, nil = gerade im Limit, spaeter noch einmal.
local function setLogging(wanted)
  nextAttempt = GetTime() + ns.ATTEMPT_INTERVAL
  local result = LoggingCombat(wanted)
  if result == nil then
    return nil
  end
  local running = result and true or false
  if running == wanted then
    logging = running
    loggingSince = running and GetTime() or nil
    nextQuery = GetTime() + ns.QUERY_INTERVAL
    return true
  end
  return false
end

-- Die Auswertung braucht Advanced Logging; der Wert steht im Kopf der Logdatei und muss also vor dem Start gesetzt sein.
local function start()
  if not advancedOn() then
    SetCVar("advancedCombatLogging", "1")
  end
  return setLogging(true)
end

-- Bemerkt /combatlog und andere Addons: Wer das Log hier ausschaltet, dem schaltet es die Automatik nicht wieder an.
local function poll(instanceId)
  local now = GetTime()
  if now < nextQuery then
    return
  end
  nextQuery = now + ns.QUERY_INTERVAL
  local value = LoggingCombat()
  if value == nil then
    return -- Im Limit: Das heisst nicht, dass das Log aus ist.
  end
  local running = value and true or false
  if running == logging then
    return
  end
  logging = running
  if running then
    loggingSince = now
  else
    loggingSince, stopAt = nil, nil
    db.startedByAddon = false
    suppressedFor = instanceId
  end
end

function ns.Evaluate()
  if not db or not apiAvailable() then
    return
  end
  local kind, instanceId = loggedInstance()
  poll(instanceId)
  local now = GetTime()

  if kind then
    stopAt = nil
    if instanceId ~= suppressedFor then
      suppressedFor = nil
    end
    if db.auto and not logging and suppressedFor == nil and failedFor ~= instanceId and now >= nextAttempt then
      local result = start()
      if result then
        db.startedByAddon = true
        failedFor = nil
        ns.Print(L.started:format(L[kind]))
      elseif result == false then
        failedFor = instanceId
        ns.Print(L.failed)
      end
    end
  elseif logging and db.startedByAddon then
    -- Nur beenden, was der Companion selbst begonnen hat; ein von Hand gestartetes Log laeuft weiter.
    if not stopAt then
      stopAt = now + ns.STOP_GRACE
    elseif now >= stopAt and now >= nextAttempt then
      if setLogging(false) then
        stopAt = nil
        db.startedByAddon = false
        ns.Print(L.stopped)
      end
    end
  else
    stopAt = nil
  end
end

function ns.Status()
  if not apiAvailable() then
    return { state = "unavailable", auto = db and db.auto }
  end
  local kind, instanceId = loggedInstance()
  local now = GetTime()
  return {
    state = logging and "on" or "off",
    auto = db and db.auto,
    kind = kind,
    advanced = advancedOn(),
    elapsed = loggingSince and (now - loggingSince) or nil,
    stopsIn = stopAt and math.max(0, stopAt - now) or nil,
    suppressed = kind ~= nil and suppressedFor == instanceId,
  }
end

function ns.Toggle()
  if not apiAvailable() then
    ns.Print(L.missingApi)
    return
  end
  if logging then
    local _, instanceId = loggedInstance()
    if setLogging(false) then
      stopAt = nil
      db.startedByAddon = false
      suppressedFor = instanceId
      ns.Print(L.stopped)
    else
      ns.Print(L.busy)
    end
  else
    local result = start()
    if result then
      db.startedByAddon, suppressedFor, stopAt = false, nil, nil
      ns.Print(L.manualStarted)
    elseif result == false then
      ns.Print(L.failed)
    else
      ns.Print(L.busy)
    end
  end
end

function ns.SetAuto(on)
  db.auto = on
  ns.Print(on and L.autoOn or L.autoOff)
  ns.Evaluate()
end

function ns.DB()
  return db
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name ~= "ReforgeCompanion" then
      return
    end
    ReforgeCompanionDB = ReforgeCompanionDB or {}
    db = ReforgeCompanionDB
    for field, value in pairs(DEFAULTS) do
      if db[field] == nil then
        db[field] = value
      end
    end
    -- Nach /reload laeuft das Log weiter und bleibt dem Companion zugeordnet, nach einem Neustart des Spiels nicht.
    if apiAvailable() then
      nextQuery = GetTime() + ns.QUERY_INTERVAL
      local value = LoggingCombat()
      if value == nil then
        -- Im Limit ist die Antwort unbekannt: Die Zuordnung bleibt, und die naechste Abfrage bringt Klarheit.
        logging = db.startedByAddon == true
        nextQuery = GetTime()
      else
        logging = value and true or false
        if not logging then
          db.startedByAddon = false
        end
      end
      loggingSince = logging and GetTime() or nil
    end
    events:UnregisterEvent("ADDON_LOADED")
    ns.CreateWindow()
  elseif event == "PLAYER_LOGIN" then
    if not apiAvailable() then
      ns.Print(L.missingApi)
    end
    -- Ereignisse decken nicht alles ab: /combatlog meldet keines, und das Ende der Frist auch nicht.
    C_Timer.NewTicker(1, function()
      ns.Evaluate()
      ns.RefreshWindow()
    end)
    ns.Evaluate()
    ns.RefreshWindow()
  else
    ns.Evaluate()
    ns.RefreshWindow()
  end
end)
