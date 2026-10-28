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

## Locale-safe loot and Bronze-item diagnostics (development)

ComfyData now matches the full Blizzard-localized LOOT_ITEM_*_SELF template
instead of comparing just a chat-message prefix. MULTIPLE templates are
checked first, and count can be before or after the item hyperlink.
Positional localization placeholders and escaped percent signs are supported.
With old clients lacking a MULTIPLE template, an explicit xN suffix after the
item hyperlink can be counted. Zero, huge, foreign and unmatched messages
are rejected. The item link's name is saved to help identify 'Bronze' if
Forever delivers it as a bag item.

Currency API (wallet.currencies), bag-item loot (loot.items), and ordinary
coin (wallet.characters) are THREE separate kinds of rewards. We have not
verified Forever's Bronze item/currency ID or actual client events.
In-game /reload tests are still required.

Regression tests:
    lua5.1 tests/test_localized_loot.lua .
    lua5.4 tests/test_localized_loot.lua .

## Gathering provenance (development)

ComfyGatherer passes the GetLootSourceInfo GUID to ComfyData when the client exposes it. ComfyData saves lastSourceGUID and lastSourceType on gathering items and nodes (latest source only). GameObject may mean an ore vein; Creature may mean a mob drop. Missing source data does not cause gathering to be discarded. In-game tests are still required.

    lua5.1 tests/test_gather_sources.lua .
    lua5.4 tests/test_gather_sources.lua .

## Currency updates without an ID (development)

Some clients may send CURRENCY_DISPLAY_UPDATE without currencyID.
This development version refreshes **only previously recorded currency IDs**
for the current character; it also refreshes these known IDs when entering
the world after login/reload. API failures do not erase stored values, and
unknown currency IDs are never guessed or enumerated. Newly introduced
currencies still need an ID-bearing event or a verified discovery method.

Copper in the wallet, an API currency, and a bag-item token such as Bronze
remain separate tracking mechanisms until the actual Forever client confirms
which one is used.

    lua5.1 tests/test_currency_refresh.lua .
    lua5.4 tests/test_currency_refresh.lua .

Integration with game events is tested by tests/test_suite_integration.lua.
True WoW Forever event signatures and persistence require in-game /reload
verification.
