# Trinket On-Use Detection: Login Timing Investigation

Context: PIHelper's `ScanTrinkets()` (in `PIHelper.lua`) checks `C_Item.IsItemDataCachedByID(itemID)` before calling `GetItemSpell(itemID)` to detect on-use trinkets, and falls back to `Item:CreateFromItemID(itemID):ContinueOnItemLoad(...)` when data isn't cached. Scans run on `ADDON_LOADED`, `PLAYER_LOGIN`, and `PLAYER_ENTERING_WORLD`. Despite this, trinkets are sometimes not auto-detected on a full client login, while the manual "Scan" button (same code path, triggered later by the user) always finds them.

## 1. Does `IsItemDataCachedByID` returning true guarantee `GetItemSpell` will succeed?

**No.** Item "data" caching and spell caching are two independent async subsystems in the client, and `IsItemDataCachedByID` only certifies the former.

Blizzard's `AsyncCallbackSystem.lua` defines three separate permitted API types, each with its own event and its own request accessor:

```lua
local permittedAPI =
{
    [AsyncCallbackAPIType.ASYNC_QUEST] = { event = "QUEST_DATA_LOAD_RESULT", accessor = C_QuestLog.RequestLoadQuestByID },
    [AsyncCallbackAPIType.ASYNC_ITEM]  = { event = "ITEM_DATA_LOAD_RESULT",  accessor = C_Item.RequestLoadItemDataByID },
    [AsyncCallbackAPIType.ASYNC_SPELL] = { event = "SPELL_DATA_LOAD_RESULT", accessor = C_Spell.RequestLoadSpellData },
};
ItemEventListener  = CreateListener(AsyncCallbackAPIType.ASYNC_ITEM);
SpellEventListener = CreateListener(AsyncCallbackAPIType.ASYNC_SPELL);
```

`ItemMixin:IsItemDataCached()` / `C_Item.IsItemDataCachedByID` and `ItemMixin:ContinueOnItemLoad()` are wired only to the `ASYNC_ITEM` listener (`ITEM_DATA_LOAD_RESULT`). Spell data (names, descriptions — what an item's "on use" effect resolves to) has its own parallel system: `SpellMixin:IsSpellDataCached()` → `C_Spell.IsSpellDataCached`, and `SpellMixin:ContinueOnSpellLoad()` → `SpellEventListener` (`SPELL_DATA_LOAD_RESULT`). These are structurally identical patterns pointed at two different server-side caches, and Blizzard never merges the two waits.

`GetItemSpell`/`C_Item.GetItemSpell` returns `spellName, spellID` for an item's on-use effect. It is documented as "may return nothing" (the Warcraft Wiki page for `C_Item.GetItemSpell` tags it with the `MayReturnNothing` predicate) with no documented guarantee tying its success to `IsItemDataCachedByID`. Given the split-cache architecture above, the most defensible reading is: once basic item data (name/icon/quality) is cached, `GetInventoryItemID`+`IsItemDataCachedByID` tells you the item *record* exists client-side, but resolving the on-use effect's spell name can still depend on spell data that hasn't been requested/received yet — exactly the kind of data `ContinueOnItemLoad` does not wait for.

This directly explains why the addon's current guard (commit `c42ae38`, "check item cache before calling GetItemSpell") is an incomplete fix: it prevents the previously-reported *error* on truly uncached items, but does nothing about the case where item data is cached, `IsItemDataCachedByID` is true, `pcall(GetItemSpell, itemID)` succeeds (`ok = true`), and `spellName` is simply `nil` because the spell side of the cache hasn't caught up. The scan then silently classifies the slot as "not an on-use trinket" (`ScanTrinkets`'s `else` comment: *"cached, no use-spell — not an on-use trinket"*) — a false negative with no retry, since nothing in the code listens for the spell data arriving later.

Source: [AsyncCallbackSystem.lua, Blizzard_ObjectAPI (wow-ui-source, live branch)](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua), [Item.lua, Blizzard_ObjectAPI](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ObjectAPI/Mainline/Item.lua), [Spell.lua, Blizzard_ObjectAPI](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ObjectAPI/Mainline/Spell.lua), [API C_Item.GetItemSpell — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemSpell)

## 2. Does `Item:ContinueOnItemLoad()`'s callback always fire?

**No — there is a known, documented case where it never fires.** From `Item.lua`:

```lua
function ItemMixin:ContinueOnItemLoad(callbackFunction)
    self:ValidateForContinueOnItemLoad("ContinueOnItemLoad", callbackFunction);
    ItemEventListener:AddCallback(self:GetItemID(), callbackFunction);
end
```

`AsyncCallbackSystemMixin:Init` only fires queued callbacks when its event reports `success == true`; on `success == false` it calls `ClearCallbacks(id)` and the callback is dropped, never invoked:

```lua
if event == self.api.event then
    local id, success = ...;
    if success then
        self:FireCallbacks(id);
    else
        self:ClearCallbacks(id);
    end
end
```

Warcraft Wiki's `ItemMixin` page documents a concrete case of this: some item IDs (example given: itemID 17) return `true` from `C_Item.DoesItemExistByID` but the server responds to the data request with `ITEM_DATA_LOAD_RESULT` `success:false`, so `GetItemInfo` never populates and `ContinueOnItemLoad`'s callback never fires. The wiki's stated workaround is `ContinueWithCancelOnItemLoad` with an app-managed timeout, or listening to `ITEM_DATA_LOAD_RESULT` directly instead of trusting the callback alone. This is a low-probability failure mode for an actually-equipped trinket item ID (those are always valid, well-formed items), but it establishes that `ContinueOnItemLoad` is not an unconditional guarantee — it is a best-effort callback with a documented silent-failure path and no built-in timeout.

Source: [ItemMixin — Warcraft Wiki](https://warcraft.wiki.gg/wiki/ItemMixin), [AsyncCallbackSystem.lua (wow-ui-source)](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua)

## 3. Timing of `GetInventoryItemID("player", slot)` relative to login events

Warcraft Wiki's `GetInventoryItemID` page documents only the signature and return values (`itemId, unknown = GetInventoryItemID(unit, invSlotId)`, `nil` if the slot is empty) — it makes **no guarantee** about when the value becomes valid relative to `ADDON_LOADED`, `PLAYER_LOGIN`, or `PLAYER_ENTERING_WORLD`. There is no primary-source statement that equipment data is reliably populated by any specific one of these events.

This absence of a guarantee is itself informative and matches the addon's own accumulated experience recorded in its comments: the code already assumes `GetInventoryItemID` can return `nil` at `ADDON_LOADED` and `PLAYER_LOGIN` ("`GetInventoryItemID can still return nil for both ADDON_LOADED and PLAYER_LOGIN if equipment data hasn't synced yet`"), which is why `PLAYER_ENTERING_WORLD` was added — and separately, the addon already listens to `PLAYER_EQUIPMENT_CHANGED` for slots 13/14, which is the one event Blizzard explicitly fires with an inventory-slot argument specifically when a slot's contents change (documented on Warcraft Wiki as passing the equipment slot index). No primary source claims `PLAYER_ENTERING_WORLD` is a hard synchronization point for inventory data on a **full client login** (as opposed to a reload or zone change) — full logins additionally wait on server-side character data streaming (talents, currencies, equipment) that isn't tied to the `PLAYER_ENTERING_WORLD` contract at all. In short: `PLAYER_ENTERING_WORLD` narrows the race window but nothing in the API docs makes it airtight for a cold login.

Source: [API GetInventoryItemID — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GetInventoryItemID), addon's own code comments in `/home/mcrispen/projects/PIHelper/PIHelper.lua` (lines 202–211).

## 4. What do other addons / Blizzard do for reliable on-use detection at login?

Blizzard's own FrameXML never needs to solve exactly this problem (there's no first-party "auto-detect on-use trinkets" feature), but its item/spell display code consistently follows the same two-step pattern found in `Item.lua`/`Spell.lua`: wait for item data via `ContinueOnItemLoad`, and **separately** wait for spell data via `Spell:CreateFromSpellID(spellID):ContinueOnSpellLoad(callback)` whenever spell text/name is needed and not just an ID. Multiple FrameXML modules (`Blizzard_Soulbinds`, `Blizzard_ProfessionsBook`, `Blizzard_TorghastLevelPicker`, `Blizzard_DelvesDifficultyPicker`) use `ContinueOnSpellLoad` for exactly this reason — item data being ready does not imply spell data is ready, so Blizzard's own code treats them as two waits, not one.

Community practice for the general "`GetItemInfo`/`GetItemSpell` returns nil right after login" problem is well documented: register `GET_ITEM_INFO_RECEIVED` (fired when `GetItemInfo` requests an uncached item and the server responds) and retry the lookup when it fires for the matching item, rather than trusting a single check-once-then-scan attempt. This event is **not deprecated** — Warcraft Wiki lists it as present through the current Mainline version (12.1.0) with no removal notice. The `SPELL_DATA_LOAD_RESULT` event (the spell-side analogue, backing `ContinueOnSpellLoad`) is likewise present and undeprecated.

For this addon's specific shape of the bug — item data cached, spell data not — the correct low-level analogue of `ContinueOnItemLoad` for the missing half of the wait is `SpellMixin:ContinueOnSpellLoad`, which requires a `spellID` to construct from. Since `GetItemSpell` is exactly the call that may not have resolved yet, the practical, addon-level equivalent (used by e.g. the community pattern above) is to listen directly for `GET_ITEM_INFO_RECEIVED` and `SPELL_DATA_LOAD_RESULT` as global fallback signals and re-run the existing scan when either fires — this needs no polling loop and reuses events Blizzard already fires the moment either half of the data arrives.

Source: [ItemMixin — Warcraft Wiki](https://warcraft.wiki.gg/wiki/ItemMixin) (workaround note), [GET_ITEM_INFO_RECEIVED — Warcraft Wiki](https://warcraft.wiki.gg/wiki/GET_ITEM_INFO_RECEIVED), [C_Spell.RequestLoadSpellData — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_Spell.RequestLoadSpellData), `ContinueOnSpellLoad` call sites in [Blizzard_Soulbinds](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Soulbinds/Blizzard_SoulbindsNode.lua), [Blizzard_ProfessionsBook](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ProfessionsBook/Blizzard_ProfessionsBook.lua), [Blizzard_TorghastLevelPicker](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_TorghastLevelPicker/Blizzard_TorghastLevelPicker.lua) (wow-ui-source, live branch).

## 5. Anything patch-12.0-specific relevant to this bug?

Checked Warcraft Wiki's `Patch_12.0.0/API_changes` and `Patch_12.0.0/Planned_API_changes` pages directly. The only `C_Item` changes listed for 12.0.0 are `C_Item.IsItemBindToAccount` (added), `C_Item.CanItemTransmogAppearance` (added a second `errorCode` return), and `C_Item.GetItemInfo` (added an 18th return, `itemDescription`). **No changes to `GetItemSpell`, `IsItemDataCachedByID`, `GetInventoryItemID`, or the item/spell async-load system were found for 12.0.** `GetItemSpell` itself was deprecated back in Patch 10.2.6 in favor of `C_Item.GetItemSpell` (unrelated to 12.0, and already correctly handled by this addon's fallback shim at the top of `PIHelper.lua`).

The new `C_Secrets` namespace added in 12.0 (confirmed present: `GetSpellCooldownSecrecy`, `ShouldCooldownsBeSecret`, `ShouldSpellCooldownBeSecret`, etc., plus the broader "Secret Values" execution-taint system) is entirely about hiding **cooldown/aura/cast secrecy** for combat-log-adjacent automation prevention (crowd-control durations, PvP trinket cooldowns for other units, etc.) — it governs values, not item/spell *data caching*, and none of it touches `GetItemSpell`, `GetInventoryItemID`, or the item-data cache. This system is not implicated in the trinket-detection bug.

Conclusion: patch 12.0 introduces nothing new that explains or changes this specific race condition. The root cause is the pre-existing (and undocumented-as-guaranteed) split between item-data caching and spell-data caching described in Q1, not a 12.0 regression.

Source: [Patch 12.0.0/API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes), [Patch 12.0.0/Planned API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes), [GetItemSpell — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GetItemSpell) (deprecation note, Patch 10.2.6).

## Recommendation

Root cause: `ScanTrinkets()`'s cache guard (`C_Item.IsItemDataCachedByID`) only proves *item* data is cached. It says nothing about whether the on-use effect's *spell* data is cached, and `GetItemSpell` can legitimately return `nil` for that reason alone — not as an error (so `pcall` doesn't catch it) and not as an uncached-item case (so `ContinueOnItemLoad` doesn't fire again for it). Right after a full login, this is exactly the state a slow item→spell resolution leaves the scan in: item found, no error, `spellName` is `nil`, slot silently recorded as "no on-use effect." No code path re-checks it later unless the player re-equips the trinket (`PLAYER_EQUIPMENT_CHANGED`) or clicks Scan (which, by then, has had time for the spell cache to catch up). Swapping which login event triggers the scan cannot fix this, because the missing piece isn't "scan too early," it's "nothing listens for the specific signal that the spell data arrived."

Minimal fix: add two more event registrations to the existing `frame`/`eventHandlers` table in `PIHelper.lua`, reusing the already-existing `RescanAndUpdate()` path — no changes needed to `ScanTrinkets()` itself:

```lua
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
```

```lua
GET_ITEM_INFO_RECEIVED = function(itemID, success)
    if success and not next(PIHelper_Trinkets) then
        RescanAndUpdate()
    end
end,

SPELL_DATA_LOAD_RESULT = function(spellID, success)
    if success and not next(PIHelper_Trinkets) then
        RescanAndUpdate()
    end
end,
```

The `not next(PIHelper_Trinkets)` guard keeps this cheap (both events can fire frequently for unrelated items/spells elsewhere in the UI) by only re-scanning while the addon still has nothing detected — once a scan succeeds, these handlers become no-ops, mirroring the existing "skip unchanged" pattern already used in `PIHelper_UpdateMacro`. This directly targets the confirmed gap: `GET_ITEM_INFO_RECEIVED` catches the item-data-arrives case (a safety net alongside the existing `ContinueOnItemLoad`, since Q2 shows that path can silently never fire), and `SPELL_DATA_LOAD_RESULT` catches the previously-unhandled spell-data-arrives case identified in Q1 — the actual missing half of the wait. Both events are confirmed present and undeprecated in current Mainline (12.1.0) per Warcraft Wiki.
