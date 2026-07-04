# In Character

In-character RP discovery for World of Warcraft Retail — ambient beacons and notice boards that complement (never replace) Total RP 3.

**Version:** 0.1.0 (MVP+)  
**Target:** Retail WoW 12.0.7+

---

## Install (development)

1. Clone this repo to `C:\Users\kvebe\InCharacter`
2. Create a junction into your WoW AddOns folder (run PowerShell **as Administrator**):

```powershell
New-Item -ItemType Junction `
  -Path "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\InCharacter" `
  -Target "C:\Users\kvebe\InCharacter\InCharacter"
```

3. Enable **In Character** on the character select AddOns screen
4. `/reload` in-game

**Standalone:** Works without Total RP 3. TRP3 profile fields are used as optional editor defaults when present.

---

## Slash commands

| Command | Description |
|---|---|
| `/ic` | Open the discovery flyout |
| `/ic beacon` | Open beacon editor |
| `/ic notice` | Open notice editor |
| `/ic ping` | Test addon comms (dev) |
| `/ic history` | View draft history |

---

## GitHub

https://github.com/khallammarellus-rgb/In-Character

```powershell
git clone https://github.com/khallammarellus-rgb/In-Character.git
```

---

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full build spec.

## Testing

See [docs/testing.md](docs/testing.md) for the in-game smoke-test checklist.