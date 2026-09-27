# ComfyData

**Version 0.3 – Beta**  
**Target: World of Warcraft: Forever 1.60.1 / Interface 16001**

ComfyData is the persistent background database/API for the Comfy Suite.

It intentionally has almost no UI. Other Comfy addons read and write through the ComfyData API.

## 0.3 Beta

- Deduplicates a gathering node visit when one gathering action yields multiple item stacks.
- Stores zone names alongside map IDs for cleaner Gatherer tooltips and statistics.

## Stored data

- character identity, realm, class, faction and level
- current money, session delta and tracked positive gains
- free / maximum normal bag slots
- XP, max XP, rested XP and tracked XP gains
- total played time
- PvP session and lifetime honorable kills
- equipped-item durability
- reputation snapshots
- session/last-fight/tracked combat damage and DPS
- mob-kill database for ComfyKills
- gathering nodes/items/zones/sessions for ComfyGatherer

## Database safety

ComfyData 0.2 uses schema migrations and preserves unknown fields. Before a schema migration it asks **ComfyDataVault** for a full snapshot.

The live database is `ComfyDataDB.lua`; Vault backups are separately stored in `ComfyDataVaultDB.lua`. Both live in WoW's account `WTF/SavedVariables` area, not in `Interface/AddOns`.

Replacing/updating the addon folder does not overwrite the data.

## Commands

- `/cdata` – database status
- `/cdata snapshot` – create a Vault snapshot
- `/cdata restore` – restore the newest valid Vault snapshot; then `/reload`

External backups of the WoW `WTF` folder are still recommended against disk loss or an accidental WTF reset.
