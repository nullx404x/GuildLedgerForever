# Changelog

## 0.4.6

- Update the client API audit for WoW Forever 1.60.1, build 70888, Interface 16001.
- Stop queued sync whispers and retries when a guild member goes offline or the client reports that the player is unavailable. Resume after they reconnect, without discarding cached character data or settings.
- Give member sync, guild messages, replies and map updates turns within one sending budget. Account for other addon/chat traffic and handle client throttling without letting one unavailable recipient block everyone else.
- Queue incoming catch-up requests instead of immediately producing a burst of replies. Keep comparisons moving while records change, and avoid requesting your own character snapshots from other members.
- Prefer members with more complete shared data when filling an empty cache. Keep incomplete helpers from repeatedly redirecting newcomers through partial snapshots.
- Skip repeated profile listings when both members already have matching profiles, while continuing to check recipes and other shared records.
- Combine simultaneous requests for the same character profiles and recipe definitions into bounded guild replies. Keep equipment and recipe-book transfers targeted, and recover missed shared replies normally.
- Keep recipe transfers active while useful data arrives, accept delayed definitions that are still needed, and retain the donor slot until the receiver confirms completion.
- Stop republishing unchanged character snapshots every fifteen minutes. Routine scans keep their existing revision and update time until the data changes.
- Keep small character and recipe changes responsive during larger transfers. Recover missed guild settings without every officer sending the same reply.
- Protect your current character snapshots from remote replacement. Reject invalid record metadata and implausible revisions before starting recipe recovery.
- On a fresh installation, pause loot capture and sharing until the guild master supplies the guild's loot setting. Previously learned settings remain in effect through reloads and loading screens.
- Order officer-permission updates so a delayed older grant cannot undo a newer revocation. Recover missed permission revisions even when the visible rank selections match.
- Preserve existing settings, Discord invites, officer configuration and valid cached guild data. Keep all required libraries bundled.

## 0.4.5

- Recover member profiles and professions when a guild-wide introduction is missed, using bounded direct discovery and the existing background catch-up limits.
- Show a waiting state while a member's introduction is missing, and include introduction/profile/background-check state in copied diagnostics.
- Keep ordinary online-status and location changes from interrupting transfers or restarting shared-data comparisons. Validate membership and rank changes before accepting further data.
- Update individual roster members and preserve unrelated crafting/loot list caches. Spread routine maintenance across time and use slower safety scans alongside immediate character-change events.
- Use compact introductions between updated clients, with automatic support for older 0.4.x peers. Track member detection, identification, active transfers and completed checks separately.
- Include small personal talent/profession updates in the existing change notification, so active catch-up does not delay them or make every member request a separate copy. Preserve pending character updates when the guild loot feed is switched off or on.
- Keep a bounded queue of direct character and recipe updates during busy catch-up. Stop redundant catalog transfers when the local data already matches the other member.
- Broadcast changed Discord, loot-quality and officer-access settings once to the guild, while retaining targeted recovery for members that missed them.
- Reuse identical recipe-definition replies that are still waiting to send, so repeated requests cannot fill a busy crafter's outgoing queue with duplicate answers.
- Check whether guild settings differ before resending them during member-data catch-up, using the same recovery limits as normal discovery.
- Require source-matched release checks, including real login/roster/timer simulations, busy-guild activity, loading screens, interrupted messages and older peers before packaging or tagging a release.

## 0.4.4

- Verify compatibility with WoW Forever's live 1.60.1 client (build 70790, Interface 16001) and update installation guidance for the live client folder.
- Reduce background sync replies when members already have matching data. Share small loot updates in one guild broadcast instead of each member requesting them separately.
- Keep differing gear caches from triggering whole-guild comparisons. Fetch gear on demand and recover missed updates from online owners, while preserving the existing sync path for older 0.4.x clients.
- Improve catch-up when many addon users log in together: wait for local comparisons, back off from busy sources and retry stalled requests while keeping transfer limits.
- Recover missed Discord, officer-permission, announcement and loot-setting updates even when members already have matching character data. Coordinate policy replies so settled members stay quiet.
- Check all seven profession slots supported by the live client, including gaps in the profession list.
- Preserve current settings and cached guild data, remain compatible with 0.4.x peers, and keep all required libraries bundled.

## 0.4.3

- Refresh the interface with cleaner navigation, fewer borders, sharper text, compact talent summaries and clearer materials/crafter sections.
- Reorganize Settings into General, Your character, Guild map, Officer tools, Guild management, and Help & diagnostics. Preserve existing preferences and permissions.
- Show online members' locations beside their level and class, with location search and full text on hover.
- Show native recipe tooltips in the crafting list; keep finished-item and material tooltips in the details panel. Preserve shift-click item links and tooltips after selection.
- Add four-second guild announcements using WoW's raid-warning display, with local preview, optional sound, separate rank permissions and a leader-controlled on/off switch. No announcement cooldown or saved message history.
- Let the guild leader hide the loot feed and stop loot capture/sharing. Existing history remains until normal expiry. Members need this update to honor the switch.
- Add promotion previews for recently connected addon users, a target rank and individual confirmation for each promotion. Skip members already at that rank or higher and respect native guild permissions.
- Add a brief first-use introduction, clearer empty states, tab-specific search/page memory, disabled-button explanations and guild-setting save feedback.
- Improve guild information wrapping and diagnostics layout. Keep self-loot capture working through temporary roster refreshes.
- Keep the addon standalone with bundled libraries. Preserve saved settings, Discord invites and officer configuration.

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
