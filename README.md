# Supercharged menu (filippaldo.menu)

A fork of the Omarchy command menu that answers questions instead of only
finding commands.

The stock menu is a launcher: you type, it filters, you pick. Everything below
is what this fork adds on top — searches that come back with an **answer** at
the head of the list. Enter copies it, or acts on it. Everything the stock menu
does (apps, themes, system commands, all of `omarchy-menu.jsonc`) still works
exactly as before.

## Features

### Open links and search the web

| Type | Get |
| --- | --- |
| `github.com/dzhibas` | Opens it in your browser |
| `https://claude.ai/code` | Opens it |
| `localhost:3000` | Opens it |
| *anything with no matches* | **Search the web** — no more dead-end "No matches" |

<img width="610" height="278" alt="image" src="https://github.com/user-attachments/assets/0337630e-cdc9-4c18-92b7-da767598ead9" />

Bare domains are recognised only for known top-level domains, so `MenuModel.js`
and `install.sh` stay ordinary searches. Links open with
`omarchy-launch-browser`, which resolves your default browser and focuses the
window. Web search goes to DuckDuckGo — change `webSearchTemplate` in
`Menu.qml` for anything else.

### Unit conversion

| Type | Get |
| --- | --- |
| `100 km to miles` | `62.1371 mi` |
| `20 c to f` | `68 °F` |
| `5 gb to mb` | `5000 MB` |
| `1 tb to gib` | `931.323 GiB` |
| `70 kg to lb` | `154.324 lb` |
| `2 cup to ml` | `473.176 ml` |

Length, mass, volume, temperature, data, speed, time and area. Data covers both
the decimal (`kb mb gb tb`) and binary (`kib mib gib tib`) ladders, because the
difference between them is most of why anyone asks. Units take their full names
too — `miles`, `pounds`, `celsius`, `kilometres`. No network, no cache.

<img width="612" height="282" alt="image" src="https://github.com/user-attachments/assets/f60d7032-64c6-4937-9747-5b89fad21d59" />

### Time zones

| Type | Get |
| --- | --- |
| `time in tokyo` | `18:13` · `Asia/Tokyo · 6 hours ahead` |
| `now in utc` | `09:13` · `UTC · 3 hours behind` |
| `time in pst` | `02:13` · `America/Los_Angeles · 10 hours behind` |

Any city the system knows — the zone list comes from `timedatectl` — plus the
usual abbreviations (`utc`, `cet`, `est`, `pst`, `ist`, `jst`, `aest`). The day
is shown alongside the time when it isn't today's.

<img width="616" height="281" alt="image" src="https://github.com/user-attachments/assets/29ff9d9f-d45c-40e3-9924-8f449788ea0f" />

### Developer utilities

| Type | Get |
| --- | --- |
| `uuid` | A random UUID v4 |
| `password 24` | A 24-character password |
| `sha256 omarchy` | `382a803dcc0de9…` |
| `base64 hello world` | `aGVsbG8gd29ybGQ=` |
| `b64d aGVsbG8=` | `hello` |
| `urlencode a b&c` | `a%20b%26c` |
| `urldecode a%20b` | `a b` |
| `epoch` | Current epoch seconds |
| `epoch 1787875351` | `Fri 28 Aug 2026 03:02:31` |

Keywords: `uuid` `password` `sha256` `base64` `b64` `b64d` `unbase64`
`urlencode` `urldecode` `epoch`.

Random bytes come from `/dev/urandom`, not `Math.random`, so `password` is
worth trusting. The answer holds still while you finish typing and is new the
next time you open the menu.

<img width="607" height="654" alt="image" src="https://github.com/user-attachments/assets/78eb2f0b-4b61-48d3-9a3b-1ae759c5ac09" />


### Kill a process

| Type | Get |
| --- | --- |
| `kill chromium` | The matching processes, with pid, CPU and memory |

Enter sends `SIGTERM`. Nothing runs `ps` until `kill` is typed, and the listing
is reused for a few seconds rather than re-run on every keystroke.

<img width="612" height="285" alt="image" src="https://github.com/user-attachments/assets/9d0e490d-c74d-466c-82a9-f0d05adf9f27" />

### Calculator

| Type | Get |
| --- | --- |
| `2+3` | `5` |
| `sqrt(144)+2^8` | `268` |
| `(1920*1080)/2` | `1036800` |

Operators `+ - * / % ^`, parentheses, unary signs, the constants `pi` `tau` `e`,
and the functions `sqrt cbrt abs round floor ceil exp ln log log2 sin cos tan
asin acos atan`.

The expression is parsed by hand rather than handed to the JavaScript engine
that runs your shell — nothing typed into the search field is ever evaluated as
code. A bare number stays a search term.

<img width="620" height="270" alt="image" src="https://github.com/user-attachments/assets/6105d637-7315-492e-b1c2-05b2fa274d4a" />

### Currency conversion

| Type | Get |
| --- | --- |
| `123 eur to usd` | `143.31 USD` · `123 EUR at 1.1651 · 28 Aug` |
| `123USD to eur` | `105.57 EUR` |
| `$120 to eur` | `102.99 EUR` |
| `50 euros to dollars` | `58.26 USD` |
| `(20+5) eur to usd` | `29.13 USD` |
| `eur to usd` | Today's rate for one unit |

<img width="611" height="268" alt="image" src="https://github.com/user-attachments/assets/df5c3676-fd7e-4ed7-8e86-781193adb4ca" />

166 currencies, any pair. Codes, symbols (`$ € £ ¥ ₹ ₽ ₴ zł`) and names all
work, and the amount can be any expression the calculator understands.

Rates come from [exchangerate-api's free daily
endpoint](https://open.er-api.com/v6/latest/EUR) — no API key — and are cached
at `~/.cache/omarchy/menu-exchange-rates.json`. **The fetch happens the first
time you actually type a conversion**, so a menu never used as a converter
never touches the network; after that it refreshes about once a day. Offline,
the row says so rather than showing a stale number without warning.

Commas are not accepted in amounts: `1,000` means one thousand in half of
Europe and one-point-nought in the other half, and neither reading is worth
guessing at. Crypto is not supported — the rate source is fiat only.

## Origin and local changes

Forked from [dzhibas/omarchy.dzhibas.menu](https://github.com/dzhibas/omarchy.dzhibas.menu)
v1.3.4 (MIT, see `LICENSE`). Rather than installing it as-is, the fork was
three-way merged against the menu plugin shipped with the Omarchy installed
here, so the upstream changes made since the fork point are in:

- `checked:` guard results and the ✓ marker, and the guard batch that evaluates
  them
- the delete-confirmation flow (`deleteConfirmOpen` / `deleteTarget`)
- `FileView`-watched JSONC sources, so live edits to `omarchy-menu.jsonc` apply
  without a restart
- the cursor model (`cursorActive`, `nextSelectable`, `settleCursor`)

Local fixes on top of the merge:

- The upstream menu dropped `disabled:` guard support, which the fork's base
  still had. The guard-derived `disabledResults` is gone, but the per-row
  `disabled` flag stays: the fork's query rows use it while they wait on
  something (rates still loading), and `rowSelectable` reads it. `displayRow`
  and the dmenu rows now declare the role explicitly, because a QML `ListModel`
  fixes its roles on the first row appended and a row that omits one silently
  loses it.
- Two `textFormat: Text.PlainText` assignments were duplicated by the merge
  ("Property value set multiple times" on load); the extras are removed.
- `sanitizeText` and `sanitizeRow` are exported from `MenuModel.js`, so the
  untrusted-text handling can be tested outside the shell.
- **The Apps submenu.** The host injects `shell.appLibrary` only into
  first-party menus; a clone is third-party, gets a scoped `PluginShellApi`,
  and reads it as `null`, so `mergeAppRows()` returned at its first line and
  Apps was permanently empty. Confirmed to be the host rather than this fork
  by running unmodified stock `Menu.qml` under this plugin's id: still null.
  The submenu now falls back to the `DesktopEntries` Quickshell singleton,
  which no injection gates, and reproduces what `AppLibrary` wrapped:
  `NoDisplay` plus the `launcher.hides` list are filtered, entries are sorted
  by name, icons resolve through `Quickshell.iconPath`, launching runs the
  same `uwsm-app -- gtk-launch <id>.desktop`, and removal the same
  `omarchy-remove-launcher-entry`. An injected library is still preferred when
  there is one — it also carries the launch OSD and a live icon index that a
  plugin cannot rebuild. What the fallback gives up is exactly those two.

## Ctrl+R rerolls a generated answer

`password`, `uuid` and a bare `epoch` draw a fresh answer; the rest of the
utilities are a function of what was typed. Ctrl+R drops the cached answer for
the current query and lets the row draw another, and the row says so
(`20 random characters · Ctrl+R for another`).

Only the drawing keywords take the key. Ctrl+R on `sha256 omarchy` would
redraw the same digest, so the shortcut is not claimed there and stays free
for anything else bound to it. The answer still holds still while you finish
typing — the reroll is the one thing that changes it.

## Web search follows the browser

The fallback row for a search that matched nothing no longer names an engine.
It hands the query to the browser prefixed with `?`, which is what a
Chromium address bar reads as "search with the configured engine", so the
menu uses whatever is set there and keeps using it after a change. The stock
fork hardcoded DuckDuckGo in `webSearchTemplate`.

Parsing the browser's own configuration was the alternative and was rejected:
Chrome stores its engine as a template full of `{google:baseURL}`-style
placeholders that only Chrome expands, in a per-profile `Preferences` file,
and Firefox stores it in a compressed blob in a different format again.

The prefix is Chromium-family syntax. Firefox does not accept it from the
command line and falls back to `webSearchTemplate`, as does setting
`webSearchUsesBrowserDefault` to `false`.

## Apps stay in their own menu

`appsInRootSearch` (near the dials below) is `false`, so application rows are
dropped from a search made outside the Apps submenu. With hundreds of desktop
entries a search from the root came back mostly applications, with the command
actually wanted buried under them.

Nothing becomes unreachable: the Apps row in the root menu is untouched, and
once inside Apps (`SUPER + ALT + SPACE`, stock binding) every app is searchable
as before. The apps provider is also skipped entirely for a search that would
discard its rows, so the root search stops enumerating desktop entries.

Set `appsInRootSearch` to `true` for the stock behaviour.

## Geometry

The card's size lives in one block near the top of `Menu.qml`, so a redesign
is an edit there rather than a hunt through the delegate:

| Dial | Here | Stock | Effect |
| --- | --- | --- | --- |
| `menuFontScale` | `0.85` | `1.0` | every text and icon size in the card |
| `menuCardWidth` | `360` | `300` | card width, in `Style.space()` units |
| `menuHeightFraction` | `0.5` | `0.7` | most of the screen the row list may take |

Row height follows the font: the stock minimums (50 and 58) were sized for
full-size text, and left alone they hold the rows tall while the labels shrink
inside them, which reads as padding rather than a smaller menu. The icon
column scales with the glyph for the same reason.

These are deliberately local rather than themed. The shell's own `Style`
tokens are shared with the bar and every panel, so shrinking the menu through
them would shrink those too.

Saving the file reloads the plugin; give it a few seconds. If a geometry
change does not appear, `omarchy restart shell`.

## Install

The manifest declares `kinds: ["menu"]` only, with no `bar-widget`. That is
deliberate. A third-party plugin counts as enabled only while shell.json
mentions it somewhere, so deleting its bar entry switches the whole plugin off
(`PluginRegistry.isEnabled()` ends in `findEntryLocation(...).found`; the
`__isFirstParty` exemption above it is why the stock menu survives losing its
button). Declaring no widget kind sends `omarchy plugin enable` down the
`config.plugins.push(entry)` branch instead of the bar-layout one, so the menu
lands where it keeps working and the bar is never touched.

`BarWidget.qml` is kept for reference. To put the button back, add
`"bar-widget"` to `kinds`, `"barWidget": "BarWidget.qml"` to `entryPoints`,
and a `barWidget` block with a `displayName`.

This is a local plugin at `~/.config/omarchy/plugins/filippaldo.menu`. After
editing any file here the shell reloads it automatically; force one with:

```bash
omarchy-shell shell rescanPlugins
```

The bar button glyph is `\uf011` in `BarWidget.qml` (the stock menu uses
`\ue900`, the Omarchy mark).
