# Guild Ledger

A standalone guild roster, crafting directory and shared loot feed for **WoW Forever (Camelot)**. Target client: **1.60.1, build 70450, Interface 16001**. Other WoW clients are not verified.

## Install or update

1. Close WoW, then extract the release ZIP into your Forever client's `Interface/AddOns/` directory (normally `_classic_beta_/Interface/AddOns/`).
2. Confirm `AddOns/GuildLedger/GuildLedger_Camelot.toc` exists without an extra nested folder.
3. Enable Guild Ledger, log in, and type `/gl` or click the minimap book.
4. Open each of your profession windows once to share learned recipes.

For an update, replace the existing **GuildLedger addon folder**. This first-release build clears old development caches once, while retaining personal settings, the Discord invite and officer configuration. Gear and talent details rebuild from scans; open profession windows to repopulate recipes. Old loot history is discarded. Back up SavedVariables before downgrading: older releases do not understand the new compact format. Keep your `WTF` folder and SavedVariables: these hold your settings and cached guild data. All required libraries are included; no separate addon, service, account or desktop companion is needed.

## Roster

Browse compact character rows with level, class, specialization, role and profession summaries. The roster initially shows online members; choose All members to include offline characters. Search and combine class, spec and role filters. Select a character for Spec, Gear, Professions or Loot details.

Spec shows the talent-point split and a short build summary. Recognized specs suggest roles automatically; personal Settings lets each player override them. Feral suggests Tank and DPS. Unknown or unrecognized builds remain unassigned. Opening Gear requests equipped slots from the member or a connected peer holding their snapshot; an unavailable item is different from an empty slot. Previously fetched equipment stays cached and can be viewed offline, with its last scan time. If nobody connected holds an uncached member's gear, it remains unavailable until a suitable peer connects.

## Crafting

Each recipe appears once. Search by item or crafter, and filter by profession, rarity or online availability. Hover the list for the recipe tooltip; the details panel shows the finished item. Select a recipe to see its required ingredients and the guild members who can craft it. Whisper opens a chat editor; it does not send a message.

The binding filter defaults to **Hide BoP**, keeping Bind on Equip items, unbound consumables and enchant services visible. Choose **BoE only**, **BoP only**, **All bindings** or **Unknown binding** as needed. The default hides confirmed Bind on Pickup outputs; it is not a guarantee every remaining output can be traded. Uncached items remain visible until binding data loads. Your selection is saved; Clear restores Hide BoP.

Recipe lists update when members open their own profession windows. Ingredients describe the recipe requirements only. **Guild Ledger never reads or shares bag contents, bank contents or material availability.**

## Guild Loot

The guild leader can disable the feed in Officer tools. This hides loot views and stops capture and sharing for members on 0.4.3 or newer. Existing records remain until their normal expiry.

One shared feed, newest first, keeps **up to 500 loot records for seven days**. The default is Rare (blue) and above. The guild master can allow officer ranks to manage the feed in **Settings > Officer tools**; authorized officers can include Uncommon (green) and above. There are no personal loot filters.

Each participating member records their own qualifying self-loot messages and shares them. Quest rewards, dungeon loot and drops can appear when the client emits a supported self-loot/pushed-item message. The addon does not reconstruct past loot or infer loot from equipment. Members without the addon do not contribute their own captures. Trading does not rewrite the original recipient. Exact event delivery depends on the client and locale.

Guild policy is learned from online authorized members. A new installation must meet the guild master online to receive officer-rank permissions. Previously learned settings persist through reloads and loading screens. Version 0.4.0 uses a new sync protocol. Guild members must update to 0.4.0 or a compatible newer release to exchange data, policy and map positions. Older development protocols are ignored entirely.

## Discord and settings

The **Discord** button opens a copyable invite. The guild master uses **Settings > Guild management > Discord** to save a Discord invite URL or clear it. New installations start without an invite. The invite is scoped to the current guild and is shared directly by the guild master with online members running compatible 0.4.0-or-newer versions. Members retain the last received invite when the guild master logs out; new members must meet the guild master online to learn it. Existing saved invites survive the update.

Personal Settings includes role overrides, minimap visibility and window scale. Drag the minimap button around the map and drag the main window to reposition it. Escape closes the main window. Assign an optional shortcut through WoW's Key Bindings. Items and spells use native WoW tooltips, allowing other tooltip addons to customize them. Shift-click an item to insert its link into an active chat edit box.

## Guild members on the map

**Guild map: shown** and **Share location: on** are enabled by default. In Settings, turn either off to hide guild markers or stop sharing your own character's position. Previously saved choices are preserved. The world map also has a **Guild members** checkbox for visibility.

Small class-colored diamonds appear on supported zone and related continent maps. Hover for a two-line tooltip with name, level, class and known spec. Updates are sent at most once per 30-second periodic interval; disabling sharing sends a hide notice when connected. Offline members are hidden and positions expire after 90 seconds. Loading screens and instances withdraw your marker. No location history is saved, and locations are never relayed by other members. Members must run compatible 0.4.0-or-newer versions to contribute. Separate phases are not resolved; markers are approximate recent positions, not a guarantee the character is visible in your phase.

## Guild announcements

Open Settings â†’ Officer settings â†’ Announcements. The guild leader and ranks granted announcement access can preview a message locally or send it to online guild members using this feature. Messages use WoW's native raid-warning display for four seconds. Warning sound is on by default; the sender can switch it off for silent announcements, and Preview uses the same choice. The choice is saved for that sender. Sound respects the game's sound settings.

The guild leader can turn announcements off for everyone. Officer access has separate rank selections for managing loot and sending announcements. Existing officer grants are used initially; choosing announcement access or changing loot access separates them. Sending does not require a raid group. Messages are short plain text with no announcement cooldown. Duplicates and expired messages are ignored. Announcements are not saved or replayed on login. Members need this update to honor the new settings; a new installation learns the guild policy from the guild leader when online together.

## Commands

| Command | Action |
| --- | --- |
| `/gl` or `/guildledger` | Open or close Guild Ledger |
| `/gl settings` | Open personal settings |
| `/gl scan` | Refresh available character data and the open profession |
| `/gl sync` | Request roster refresh and throttled peer discovery |
| `/gl status` | Print client and sync status |
| `/gl diagnostics` | Open copyable troubleshooting information |
| `/gl resetpos` | Recenter the window and reset its scale |
| `/gl help` | List commands |

## Shared data and limits

Guild Ledger shares talent information, equipped items, chosen roles, professions, learned recipes, scan times and qualifying loot observations with addon users in the same guild. It does not share public/officer notes, bags or banks. Data is cached in `WTF/Account/<account>/SavedVariables/GuildLedger.lua`. A confirmed guild change clears the guild cache. Previously downloaded copies cannot be remotely revoked. These are cooperative addon records, not authenticated proof of loot or equipment.

Large guilds can take several minutes or longer to fill an empty cache. The open tab gets priority; with the window closed, online profiles and the newest 20 loot entries come first. Recipes and remaining history continue in the background. Uncached equipment is fetched when its Gear tab opens. The footer counts records checked, including deferred equipment, rather than claiming all gear has downloaded. Transfers are throttled; progress resumes after temporary interruptions and already held records are skipped. A transfer finishing does not mean every member's data is current.

Recipe definitions are shared across members; books hold compact keys both in memory and on disk. Transfers reuse shared recipe-list templates and send each member's differences, with recovery if a template is missing. Small changes are announced directly, with periodic discovery as a recovery path. Catch-up prefers one source and allows a second after a stall. Matching recent snapshots use change-only updates; otherwise the sender supplies a full snapshot. A book is limited to 600 recipes, with a guild catalog cap of 12,000 definitions and a 120 KiB decoded message limit; an oversized or failed scan preserves the previous snapshot and reports a diagnostic. Recipe alternatives and optional materials are not inferred. When the client supplies no loot-message ID, identical messages within two seconds are conservatively deduplicated.

Diagnostics reports local sync traffic, send refusals, and average/peak processing times where supported. Addon memory is sampled when you open diagnostics; its displayed peak is the largest of those samples, not a continuous memory monitor. No performance data is broadcast.

## Troubleshooting and bug reports

- **Waiting for roster:** open WoW's guild window, wait a few seconds, then `/gl sync`. Incomplete rosters pause sharing to avoid removing valid data.
- **Waiting for peers:** another guild member with the addon must be online. Repeated sync commands do not bypass throttling.
- **Missing recipes:** open each profession window, then `/gl scan`. Linked or other players' profession windows are not scanned as yours.
- **Missing gear names/icons:** allow the item cache to load, then `/gl scan` and hover again.
- **Missing green loot:** ask an authorized officer to check the guild threshold. History older than seven days or beyond the 500-record cap expires.
- **Window offscreen:** `/gl resetpos`.
- **Reporting a problem:** include addon version, client build, what happened, reproduction steps, and the exact Lua error if any. `/gl diagnostics` provides a copyable report; it includes peer character names, so review it before posting publicly.

Limited in-game UI checks and automated tests have been performed. Multi-player live acceptance testing remains incomplete; see the release checklist in the source workspace. See `CHANGELOG.md` for changes and `Libs/THIRD_PARTY.txt` for bundled-library notices.
