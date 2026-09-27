# ComfyData Changelog

## 0.2 Beta – 28.09.2026
- Promoted ComfyData from the temporary bundled build version into its own repository.
- Added schema-versioned database structure and migration history.
- Added automatic pre-migration, session-start and logout Vault snapshots when ComfyDataVault is installed.
- Added validation and recovery from the newest valid Vault snapshot.
- Added public kill and gathering storage APIs.
- Added account totals and session records.
- Preserved character, money, bags, XP, playtime, PvP kills, durability, reputation and DPS tracking from the initial prototype.
- Kept SavedVariables outside the AddOns folder so addon updates cannot overwrite stored data.
