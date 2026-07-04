# In-Character RP Discovery Addon — Architecture Spec

**Purpose of this document:** This is a build spec intended as a prompt for a coding CLI (e.g. Claude Code) to scaffold and implement a World of Warcraft addon. It is not user-facing documentation — it's the technical contract for implementation.

**Target client:** Retail WoW, patch 12.0.7+
**Companion addon (not dependency):** Total RP 3 — must function fully standalone

---

## 1. Design Philosophy (read first, applies to every decision below)

1. **In-character always.** No OOC metadata fields ("seeking LT/ST, no horror"). All player-facing text is generated or written as if spoken by the character, not the player.
2. **Complement TRP3, never replace or modify it.** Read-only, nil-checked optional integration. Separate addon message prefix. Never write to TRP3 SavedVariables. Never touch TRP3's UI or frames.
3. **Lite over feature-rich.** Every feature should be justifiable against: does this need a setting, or can it be inferred/generated? Prefer fewer, smarter defaults over configuration surface.
4. **Native-looking, not TRP3-looking.** Build UI from Blizzard's own shared templates (`BackdropTemplate`, quest fonts, standard tooltip backdrop) — borrow the game's visual language, not TRP3's.
5. **Subtle at rest, immersive when engaged.** No ambient clutter (no minimap spam, no world-map pin explosion). On open, feels like a native game panel (objective tracker, quest board), not an addon window.
6. **No live server, no internet access.** Everything rides on Blizzard's addon-message/chat infrastructure. Design for graceful degradation when the origin player is offline.
7. **Scale-proof by construction.** Density of nearby players must never translate into linear UI clutter or linear message volume against a single target. Ambient signal = presence + count, never a growing list.

---

## 2. Explicit Non-Goals

- No RAG/AI text generation inside the addon (no internet access from Lua sandbox; out of scope entirely — see companion-tool note below).
- No true geographic-radius addon messaging — doesn't exist in the API; approximate via zone/subzone self-filtering.
- No persistent server-hosted board content — all data lives on player clients only.
- No editing, hooking, or reading TRP3's SavedVariables directly.
- No injecting fake options into real NPC gossip trees (server-authoritative, not addon-editable).

---

## 3. Data Model

### 3.1 Beacon (ambient, ephemeral, LFRP-style "I am here")
```
Beacon {
  id            : string (UUID)
  ownerGUID     : string
  charName      : string        -- from TRP3 if present, else unit name
  templateId    : string        -- which sentence-builder template
  slots         : table         -- filled template values (race, disposition, location, etc.)
  fullText      : string        -- resolved sentence, generated client-side
  shortText     : string        -- paired short-form fragment (NOT a truncation — generated alongside fullText)
  zoneId        : number
  subzone       : string
  coords        : {x, y}
  createdAt     : timestamp
  expiresAt     : timestamp     -- short TTL (minutes-hours; ambient, not persistent)
  status        : enum(ACTIVE, EXPIRED, DRAFT, REMOVED)
}
```

### 3.2 Notice (persistent posting — jobs, requests, opportunities)
```
Notice {
  id            : string (UUID)
  ownerGUID     : string
  charName      : string
  title         : string
  bodyText      : string        -- free text, profanity-checked
  scopeTier     : enum(INDIVIDUAL, GROUP, GUILD, FACTION)
  sealIcon      : string        -- cosmetic border/crest per scopeTier
  boardId       : string        -- which physical board/landmark this is posted to
  createdAt     : timestamp
  expiresAt     : timestamp     -- longer TTL (days), player-configurable within max cap
  editCount     : number
  status        : enum(ACTIVE, EXPIRED, DRAFT, REMOVED)
}
```

### 3.3 Board (static landmark registry — shipped with addon, not player-generated)
```
Board {
  id            : string
  zoneId        : number
  coords        : {x, y}
  displayName   : string        -- "Stormwind Hero's Call Board"
}
```
Hardcoded table, same pattern as HandyNotes/TomTom POI databases. Extend by adding entries, not by runtime discovery.

---

## 4. Communications Architecture

### 4.1 Transport assignment

| Purpose | Transport | Notes |
|---|---|---|
| Beacon presence ping | Custom hidden `CHANNEL` (own prefix, distinct from TRP3's) | Tiny payload: `id, zoneId, subzone, coords, shortText` only |
| Board query ("who has notices at board X") | Custom hidden `CHANNEL` | Fired only on proximity trigger, not polled continuously — self-limiting by nature |
| Board query response | `WHISPER` (peer-to-peer, direct to requester) | Small payload: `id, title, scopeTier` only |
| Full beacon/notice text fetch | `WHISPER` (peer-to-peer, on-demand) | Fired only when user selects an item from the flyout/board list |
| Real in-character flavor (optional, player-triggered) | `SendChatMessage` with `SAY`/`EMOTE` | MUST be called synchronously inside the same handler as the player's button click (hardware-event constraint) — cannot be fired from a timer or background event |

### 4.2 Required libraries
- **ChatThrottleLib** — mandatory for all `CHANNEL`/`WHISPER` sends. Do not call `SendAddonMessage`/`C_ChatInfo.SendAddonMessage` directly.
- **AceComm-3.0** — message chunking/reassembly for payloads exceeding 255 bytes (notice body text will routinely exceed this).
- **LibSerialize + LibDeflate** — serialize and compress structured payloads before chunking.
- **LibDBIcon** — minimap button, standard behavior (draggable, matches player expectations from other addons).
- **C_ChatInfo.SendAddonMessageLogged** — use this variant (not the unlogged one) for any transmission containing player-authored free text (Notice bodies), since Blizzard's Code of Conduct reporting pipeline depends on it.

### 4.3 Throttle assumptions (design conservatively)
- Assume per-prefix throttle (~10 message burst, refill ~1/sec) applies to all chat types, not just CHANNEL.
- Board queries fire only on proximity trigger (event-driven), not on a timer — keeps volume tied to foot traffic, not population.
- Beacon pings fire only on explicit player action (clicking Broadcast), never automatically/periodically.

### 4.4 Zone/geographic filtering pattern
No radius-broadcast primitive exists in the API. Follow TRP3's `CSCAN` pattern: broadcaster/requester embeds `zoneId`/`subzone` in the payload; every receiving client self-filters and only acts on messages relevant to their current location. This is client-side judgment, not server-enforced — document this limitation in-code and in any user-facing text ("showing known notices," not "all notices").

---

## 5. Post Lifecycle & Maintenance

```
DRAFT → (post) → ACTIVE → (expire, automatic sweep) → EXPIRED → moves to History as DRAFT
ACTIVE → (owner deletes) → broadcasts RETRACT~id → moves to History as DRAFT
DRAFT (in History) → (repost/renew) → ACTIVE (new id, new expiresAt)
ACTIVE → (edit) → opens editor → on save, treated as renew (new id, new expiresAt, re-run profanity check)
```

### Implementation notes
- **Automatic expiry**: no network message required. `expiresAt` travels embedded in the original payload. A local ticker (interval ~60s, not per-frame) sweeps the local notice/beacon table and any cached copies, flipping anything past `expiresAt` to `EXPIRED` and moving owned items to History.
- **Manual delete**: broadcast a small `RETRACT~id` on the shared channel so peers drop cached copies; move to local History (SavedVariables only, never broadcast) as `DRAFT`.
- **Renew = repost**: do not resurrect an old id. Take History draft content, assign new `id` + new `expiresAt`, broadcast as new. Collapses "renew" and "edit" into one code path — edit is renew with an editor step first.
- **Relay caching for resilience**: any client that successfully fetches a full Notice caches it locally with a timestamp and can answer board queries on the origin's behalf if the origin is offline, marked "last confirmed [time]." Never resurrect past `expiresAt` even if origin is unreachable to confirm.

---

## 6. Content Safety

### 6.1 Profanity/ERP/explicit content filter (hard gate)
- Client-side only — Blizzard's chat profanity filter does not apply to custom-frame text.
- Runs at submit time and on every edit. Hard block (submission fails), not a warning.
- Normalize input before matching: strip punctuation/spacing, collapse common leetspeak substitutions.
- Maintain blocklist as a separate, easily-updatable data file (not hardcoded inline) so it can be revised without a full addon update where possible.

### 6.2 In-character voice enforcement
- **Beacons**: solved structurally — sentence-builder templates only produce first-person/in-world phrasing. No free text in the core slots.
- **Notices**: offer an optional guided/Mad-Libs frame ("I, [name], of [place], seek...") as the primary lever — constrains structure without blocking free expression.
- **Soft linter** (flag, don't block) on free text: parenthetical OOC asides, `OOC:` tags, forum-speak (`lfg`, `irl`, `brb`), anachronistic terms. Surface as a non-blocking prompt ("this might read as out-of-character — post anyway?").
- Accept that full enforcement is a human-judgment problem — route to reporting (6.3), don't over-engineer detection.

### 6.3 Reporting
- **In-game official report**: button opens Blizzard's native report flow against the poster/message. Depends on using `SendAddonMessageLogged` (see 4.2) so Blizzard's backend has a record to act on.
- **Local mute**: instant, addon-only — hides the specific post, adds poster to a personal ignore list (SavedVariables, local only).

---

## 7. UI/UX Specification

### 7.1 At-rest state (default)
- Single minimap button (LibDBIcon), icon = scroll/wax-seal/raven (not a generic bell/exclamation).
- Glows/pulses when new beacons or notices are in scanning range. Badge shows a count only — never individual notification stacking.
- **No map or minimap pins by default.** Nothing is pinned until the player has opened and selected it from the flyout — mirrors quest-accept-then-track behavior.

### 7.2 Engaged state (on click)
- Compact flyout, not a full window. Anchored to a screen corner, translucent quest-style backdrop, `BackdropTemplate` + standard quest fonts — no custom skin/art.
- List entries show `shortText` (a distinct generated field, not a mechanical truncation of `fullText`).
- Cap visible list to ~5–6 entries with a "+N more" tail (same pattern as Blizzard's own group finder queue display).
- Selecting an entry triggers full-text peer-to-peer fetch (4.1) and, only at this point, drops a map/minimap pin for that specific item.

### 7.3 Board interaction
- Proximity-based (or event-hooked to the physical board object if a reliable interaction event can be identified during implementation — verify exact event name empirically, e.g. `GOSSIP_SHOW` or equivalent, before hardcoding).
- On trigger: fires the board query (4.1), populates a board-specific view in the same flyout style as 7.2.

### 7.4 Filtering
- **Hard exclude** (content boundaries, e.g. "no horror," "no ERP"): fully hidden, no exceptions.
- **Soft priority** (tone/genre preference): never hidden — reorders/de-emphasizes (bold+top vs. dim+bottom) rather than removing. Avoids "why is my list empty" dead feeling.
- Search is explicitly scoped to "what this client has already discovered/cached" — label it as such in UI copy, since there is no true server-wide index (see §4.4, §6.3 offline degradation).

### 7.5 Real-chat immersion hook (optional, player-initiated only)
- Broadcast button, when clicked, may optionally also fire a real `/say` or `/emote` (per 4.1's hardware-event constraint) so nearby non-addon players see natural in-character flavor text too. Purely additive — never silent, never automatic.

---

## 8. TRP3 Integration (optional, read-only, nil-checked)

- On opening the posting/beacon editor, attempt to read TRP3's current profile via its public API (name, title, race, class). Populate as **editable defaults only** — never locked fields.
- Residence is not a structured TRP3 field (lives in free-text bio) — do not attempt to auto-extract it; offer as a manually-set, remembered-per-character field in this addon instead.
- All TRP3 reads wrapped in `if TRP3_API then ... end` — addon must be fully functional with TRP3 completely absent.
- Never call into TRP3 to modify its data, hide its OOC fields, or alter its UI.

---

## 9. Addon File Structure (suggested scaffold)

```
/AddonName
  AddonName.toc
  /Libs
    ChatThrottleLib/
    AceComm-3.0/
    LibSerialize/
    LibDeflate/
    LibDBIcon-1.0/
  /Core
    Init.lua              -- addon bootstrap, saved variables setup
    Comms.lua             -- all SendAddonMessage/WHISPER/CHANNEL wrappers, throttle-wrapped
    Lifecycle.lua          -- expiry sweep ticker, retract/renew logic
    ProfanityFilter.lua    -- normalize + blocklist check
    TRP3Bridge.lua         -- nil-checked optional TRP3 reads
  /Data
    Boards.lua             -- hardcoded board/landmark coordinate table
    SentenceTemplates.lua  -- beacon phrase-builder template bank
    Blocklist.lua          -- profanity/ERP term list (separable for easy updates)
  /UI
    MinimapButton.lua
    Flyout.lua             -- compact list view (7.2)
    BoardView.lua          -- board-specific list view (7.3)
    PostEditor.lua         -- notice/beacon creation & edit UI
  /History
    History.lua            -- local draft storage, SavedVariables-backed
```

---

## 10. Build Phases

1. **Core comms + throttle layer** — get `ChatThrottleLib`/`AceComm` wrapper working with a trivial ping/pong before any feature logic.
2. **Beacon module** — sentence-builder templates, presence ping, minimap glow, flyout list, on-demand full-text fetch.
3. **Lifecycle/maintenance layer** — expiry sweep, History, retract, renew-as-repost, edit-as-renew.
4. **Profanity filter + logged transport** — wire in before Notices ship, since Notices are the free-text-heavy feature.
5. **Notice module** — board registry, board query/response, scope tiers, guided in-character frame for posting.
6. **Board proximity/interaction** — proximity trigger or event hook, board-specific flyout view.
7. **Filtering (hard exclude + soft priority)** — apply across both Beacons and Notices.
8. **Reporting** — in-game report hook + local mute list.
9. **TRP3 bridge** — read-only default population, last, since it's a nicety layered on top of a fully working standalone addon.
10. **Optional real-chat immersion hook** — `/say`/`/emote` echo tied to hardware-event-safe button click.

---

## Appendix: Explicit out-of-scope idea (tracked separately)

A RAG-based lore-grounded writing assistant (quest/book text corpus → embeddings → retrieval → LLM-generated flavor text) was discussed and intentionally excluded. It cannot run inside the addon (no file access to game archives beyond Blizzard's own API getters, no compute path for embeddings/inference, no internet access from the Lua sandbox). If pursued, it would be a separate, standalone companion web tool (bring-your-own-API-key, browser-side only) that a player uses outside the game to draft text, then pastes into this addon or TRP3 manually. Not part of this addon's build.
