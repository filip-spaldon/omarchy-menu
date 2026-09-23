# Development notes


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


## Validation

```bash
node tests/menu_unit_test.js
node tests/ai_unit_test.js
```

These suites exercise the JavaScript models and AI adapters. Use the live shell
to check QML rendering, keyboard focus, plugin registration.

## Plugin lifecycle

The manifest declares only `kinds: ["menu"]`. Enable it in `shell.json`
under `plugins`; it does not need a bar button. `omarchy.clonedFrom` remains
`omarchy.menu`, allowing existing Omarchy menu commands to resolve to this plugin.
`BarWidget.qml` is retained as an optional widget source.

Runtime settings live outside the plugin directory because writes beneath the
plugin directory trigger shell reloads. Keep screenshots and recordings outside
it while capturing, then copy the finished assets into `docs/media/`.

## Marketplace publication

The root `manifest.json`, `README.md`, `LICENSE` and `preview.png` are the
marketplace inputs. Validate a clean checkout before publishing:

```bash
omarchy plugin validate .
node tests/menu_unit_test.js
node tests/ai_unit_test.js
```

The standard installer and updater follow the repository default branch.
Submit [the repository](https://github.com/filip-spaldon/omarchy-menu) through
the [marketplace form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml)
with category **Productivity** and tags **launcher**, **quickshell**, **ai**.
The marketplace maintainer reviews and approves listings.

`omarchy.clonedFrom: "omarchy.menu"` is intentional: Omni replaces a built-in
menu and uses its existing routes and restoration behavior. Removing this field
would make the generic standalone-plugin example unsuitable for this menu.
The marketplace manifest validator accepts this metadata and the permanent
`omarchy-menu-omni` ID.
