# Changelog

## 0.4.2

- Enable guild map visibility and character location sharing by default when no preference is saved. Preserve explicit opt-outs and keep both Settings switches.

## 0.4.1

- Correct specialization icons and automatic roles, including Priest Shadow Magic. Manual role choices remain supported.
- Show shared guild locations on related zone and continent maps with small class-colored diamonds.
- Keep map markers stable during temporary roster refreshes and reuse pins when positions change.
- Show native two-line map tooltips with name, level, class and known specialization; preserve the tested hover fallback.
- Update only changed map pins, cache coordinate projections and reduce idle map work.
- Fix tooltip text helpers returning an unintended extra value.
- Preserve settings and bundled libraries; no additional addon dependencies.

## 0.4.0

- Add a saved crafting binding filter: Hide BoP (default), BoE only, BoP only, All bindings and Unknown binding. Unknown item metadata remains visible in the default view until it loads; enchant services remain visible.

- Reuse shared recipe-list templates and send member-specific differences, with bounded caches and missing-template recovery.
- Fetch uncached gear on demand; retain previously fetched snapshots and keep cached gear updated.
- Prioritize the open tab and newest loot entries; tab changes safely reorder remaining catch-up work.
- Add local traffic, processing-time and explicitly sampled memory diagnostics.
- The 900-member simulation now finishes background profiles/recipes/loot in 6m50s for matching recipe lists and 9m40s with varied books. Equipment is deferred until requested, so this is not the same payload as the previous 15m30s all-gear run. Live performance remains unverified.

- First-release storage: discard old development caches once while preserving personal settings, Discord invite, officer ranks and loot policy.
- Use compact recipe memberships in memory and on disk, backed by one shared definition catalog; remove expanded-book caches.
- Remove legacy protocol discovery, feature-capability flags and obsolete personal loot overrides.
- Unify loot records and retention, recording rarity so the officer-controlled feed stays visible while item metadata loads.
- Announce small changes directly; fetch gear/recipe deltas with full-snapshot fallback. Periodic discovery recovers missed notifications.
- Prefer one catch-up source, allow a second after a stall, and avoid repeatedly comparing a newcomer's incomplete cache while it downloads.
- Batch/compress transfers using the embedded bounded LibDeflate fork; repair missing fragments and retain strict queue, input and memory bounds.
- Prefetch three bounded manifest pages, batch acknowledgments and prioritize online profiles/gear. Show cache catch-up progress in the footer.
- Spread cold fingerprint calculations across ticks, adapt sending to client congestion, reduce traffic in combat and prevent bursts after loading screens.
- Earlier transport-only comparison: full catch-up fell from 26.3 to 15.5 simulated minutes before gear became on-demand.

## 0.3.14

- Cache sync fingerprints per immutable record, releasing replaced records through weak keys.
- Avoid timestamp-only profile publications between the existing 15-minute refreshes, while publishing real changes immediately.
- Separate roster, profile, profession and loot invalidation so gear updates reuse roster/crafting lists.
- Index recipe crafters instead of searching every recipe book for each result.
- Presence-only roster updates no longer schedule local character scans; startup, periodic and event-driven scans remain.
- Prune loot on loot writes and periodic maintenance instead of on every character/recipe update.
- Validated in a Lua 5.1 simulation with 900 members, 4,100 records and 144,000 recipe entries. In-game performance remains to be measured.

## 0.3.13

- Coalesce repeated item-data requests with a bounded pending set and retry cooldown.
- Ignore unrelated and failed item-cache events instead of rebuilding addon lists.
- Avoid scheduling UI refresh timers while the window is closed and requesting already resolved equipment again.
- Include the current addon memory reading in /gl status. Live memory-growth verification is still needed.

## 0.3.12

- Optional guild-member dots on the world map, colored by class with native hover details.
- Separate show-members and share-my-location settings, both off by default.
- Locations update every 30 seconds, expire after 90 seconds, and are hidden for offline members and inside instances.
- Only the exact zone map is supported; locations are temporary and never saved or relayed.

## 0.3.11

- Guild masters can set or remove a guild-specific Discord invite through the Discord dialog. New installations no longer include a fixed guild invite.
- Invites are shared directly by the guild master with compatible online members and retained locally for the current guild.
- Updated installation, update, privacy, loot-policy and crafting documentation.
- Added explicit addon licensing and clarified bundled-library notices.
- Release validation checks matching versions, TOCs, required files and unchanged embedded libraries before packaging.
- Kept SavedVariables schema 1 and protocol 1. Existing character and loot records remain compatible.

## 0.3.10

- Preserve guild loot and officer policy while guild membership is temporarily unavailable during loading screens.
- Keep Uncommon loot visible while its item metadata is uncached.

## 0.3.9

- Added officer-controlled Uncommon loot capture and a single guild loot feed.
- Guild master controls which ranks can manage loot policy.
- Shared history retains up to 500 entries for seven days.

## Earlier testing builds

- Compact roster with class/spec icons, level information and automatic roles with personal overrides.
- Slot-based gear details, concise specialization summaries and profession cards.
- Recipes grouped once with materials and a list of available crafters.
- Native item/spell tooltips, draggable minimap launcher, key binding, window scaling and diagnostics.
- Required launcher libraries embedded for standalone installation.
