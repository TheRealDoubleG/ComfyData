# ComfyData Changelog

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
