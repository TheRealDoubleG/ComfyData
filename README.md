# ComfyData 0.7 (development)

WoW Forever 1.60.1 / Interface 16001. Shared data collector/API for Comfy
Suite addons. Tracks character identity, gold, XP, time, PvP, bags,
reputation, combat metrics, mob kills and gathering.

New:
- Quest turn-ins (quest ID, time, character, optional XP/money reward).
- Three-second duplicate quest-event suppression.
- Player death events, via existing RecordDeath API.
- RecordLoot API for other addons, plus CHAT_MSG_LOOT collection that
  filters through Blizzard's localized SELF-loot templates.
- Schema v3 adds quests/loot tables; preserves unknown existing fields.

Database safety:
Existing populated DBs are not migrated unless ComfyDataVault confirms a
pre-migration checksum-verified snapshot. On corruption, recover from a
verified Vault snapshot or quarantine the original. If both fail, block
initialization instead of destroying the data.

Commands:
- /cdata : status
- /cdata snapshot : manual Vault snapshot
- /cdvault restore confirm : manual verified restore followed by /reload

The client only persists SavedVariables on logout/reload, not per event.
Use the external WTF backup script in the ComfyDataVault repository.

Offline tests:
lua5.1 tests/test_data.lua . ../ComfyDataVault
lua5.4 tests/test_data.lua . ../ComfyDataVault

Forever release-client validation is still needed.

## Launch-data reliability follow-up (development)

- PLAYER_MONEY polls exact wallet balance in integer copper. Positive and negative
  deltas update per-character totals and a bounded 300-change audit trail.
- CURRENCY_DISPLAY_UPDATE captures non-secret API currency quantities
  by character and currency ID where C_CurrencyInfo.GetCurrencyInfo is available.
- Removed restricted COMBAT_LOG_EVENT_UNFILTERED registration.
  ComfyKills 0.4 handles kill events with PARTY_KILL.
- ComfyData alone stores player deaths, avoiding duplicate counting.
- Capture is best effort; addon code cannot force WoW to flush SavedVariables
  to disk between logout/UI reloads. Live Forever test remains necessary.

Offline tests: lua5.1 tests/test_wallet.lua . ; lua5.4 tests/test_wallet.lua .

## Nested SavedVariables integrity safety (development)

On startup, malformed tables inside kills, gathering, quests, loot, and wallet
are treated as corruption, **not silently replaced**. Missing tables from
older releases are still created. Before loading an older verified snapshot,
ComfyData now keeps a deep copy of the *newer damaged original* in the
ComfyDataVault quarantine so recent loot/kills/copper are not overwritten
without a recoverable copy. If the quarantine is already occupied or the
Vault is unavailable, startup stops rather than destroying original data.

This is a **fail-closed** policy, not a self-healing guarantee. If the game
reports a blocked startup, preserve the entire WTF/SavedVariables folder
before attempting manual recovery. Never delete a quarantined copy to
make the warning disappear. Offline tests verify data in memory but not
real-client persistence to disk.

Test: lua5.1 tests/test_nested_data_guard.lua . ../ComfyDataVault
