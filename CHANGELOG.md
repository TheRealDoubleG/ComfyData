# ComfyData Changelog

## 0.7 (development)
- Validate direct loot and gather item IDs and quantities; reject invalid/nonnumeric/node-key data before storing in SavedVariables.
- Suppress duplicate quest completions across same-second /reload while retaining valid later repeats.
- Reject malformed quest IDs and invalid API currency balances without losing a real zero balance.
- Add strict offline Lua 5.1/5.4 regression coverage for these cases.
- Ensure unique session IDs even across repeated /reload in the same second; prevent overwrite or conflation of kill, loot, gather and session history. Add 16 Lua regression tests.
- Safely refresh already known currency IDs after CURRENCY_DISPLAY_UPDATE without ID or on world entry; preserve records on API failure.
- Add 23 targeted currency tests and 14 more cross-addon assertions for currency updates.
- Record latest verified loot-source GUID and source kind for gathering (GameObject / Creature when API supports it).
- Parse localized self-loot templates including variable count order and positional placeholders; reject invalid quantities; retain item names for token diagnostics.
- Detect damaged nested kill, quest, loot and wallet tables before any repair.
- Quarantine the full newer original before restoring an older checksum-verified snapshot;
  if quarantine is unavailable/occupied, block the automatic recovery instead of losing data.
- Copper balance ledger with income/expense history and optional currency snapshots.
- Remove forbidden combat-log listener; ComfyKills handles PARTY_KILL directly.

- Quest, player death and self-loot tracking, schema v3.
- Block unsafe auto-reset and migration without Vault backup.
- Use explicit checksum-verified restore path.
- Expanded Lua tests.

## 0.5 Beta – 28.09.2026
- Registered ComfyData in Blizzard's AddOns settings list.
- Added a lightweight status page with schema, character, kill and gathering counts.
- Kept ComfyData as a background service with no heavy configuration UI.


## 0.4 Beta – 28.09.2026
- Aligned public documentation/version references after the 0.3 gathering-data changes.


## 0.3 Beta – 28.09.2026
- Deduplicated gathering-node visits per gather action.
- Added stored zone names for gathering statistics/tooltips.


## 0.2 Beta – 28.09.2026
- Promoted ComfyData from the temporary bundled build version into its own repository.
- Added schema-versioned database structure and migration history.
- Added automatic pre-migration, session-start and logout Vault snapshots when ComfyDataVault is installed.
- Added validation and recovery from the newest valid Vault snapshot.
- Added public kill and gathering storage APIs.
- Added account totals and session records.
- Preserved character, money, bags, XP, playtime, PvP kills, durability, reputation and DPS tracking from the initial prototype.
- Kept SavedVariables outside the AddOns folder so addon updates cannot overwrite stored data.
