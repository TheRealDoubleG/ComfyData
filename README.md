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
