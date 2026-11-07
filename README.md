# reforge Companion

WoW-Addon für World of Warcraft: Forever. Es zeigt den Status des Kampflogs und schaltet das Log in Instanzen und Raids automatisch ein. Ausgeliefert wird es über die Bibliothek des [reforge-Clients](https://reforge.win).

## Verhalten

- **Einschalten:** in Instanzen und Raids, nicht in Arenen, Schlachtfeldern oder Szenarien. Advanced Combat Logging wird vorher aktiviert, weil die Auswertung es braucht.
- **Ausschalten:** erst 5 Minuten nach dem Verlassen. Jeder Start erzeugt eine neue Logdatei, ein Corpse-Run soll den Raid nicht zerteilen.
- **Von Hand gestartet:** Ein per Klick oder `/combatlog` gestartetes Log läuft weiter, bis du es selbst stoppst.
- **Von Hand gestoppt:** Die Automatik schaltet es in dieser Instanz nicht wieder ein.

## Bedienung

Linksklick aufs Fenster startet oder stoppt das Log, Rechtsklick schaltet die Automatik, Ziehen verschiebt es.

`/reforge` oder `/rfc`: `start`, `stop`, `auto`, `lock`, `show`, `hide`, `reset`

## Entwickeln

Der Ordner `ReforgeCompanion/` ist das Addon. Die Tests prüfen die Logik gegen eine nachgebaute WoW-API, ersetzen also nicht den Test im Spiel:

```sh
docker run --rm -v "$PWD:/w" -w /w --entrypoint lua nickblah/lua:5.1 tests/companion_test.lua
```

## Veröffentlichen

1. `## Version` in `ReforgeCompanion/ReforgeCompanion.toc` hochzählen. Nach einem Spiel-Patch auch `## Interface`.
2. Tag setzen, zum Beispiel `v1.0.1`.
3. In `reforge.win` den Tag in `library/catalog.json` eintragen. Mit dem nächsten Deployment bieten die Clients das Update an.
