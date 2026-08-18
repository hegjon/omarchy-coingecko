# Working notes for agents

Omarchy bar-widget plugin. This checkout *is* the installed plugin
(`~/.config/omarchy/plugins/hegjon.coingecko`), so edits are live.

## Verifying changes

- `test/lint` (qmllint over `*.qml` and `components/*.qml`), `test/test-normalize`,
  `test/test-manifest`, and `omarchy-plugin-validate .`. `shellcheck` is not
  installed locally; CI runs it (`.github/workflows/ci.yml`), or use
  `docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable --severity=warning <files>`.
- `test/fixtures/markets.json` is a captured `/coins/markets` response for
  bitcoin, ethereum, dogecoin; refresh it with the URL in `coingecko-fetch`.
- The shell hot-reloads the plugin on file change. For a trustworthy check run
  `omarchy-restart-shell`, wait ~8 s, then read
  `journalctl --user --since "30 sec ago" | grep -i coingecko` for QML errors.
- IPC: `omarchy-shell hegjon.coingecko open|close|toggle|refresh`.
- Settings for experiments: `omarchy bar set hegjon.coingecko <key> <value>`
  (booleans need `--json`). Restore the defaults afterwards.
- Screenshots: `grim -o HDMI-A-1` + `magick -crop` on the 3840×2160 monitor.
  The widget sits in the center section, so the open panel is roughly
  `-crop 720x744+1848+56` (probe the orange border with `%[pixel:p{x,y}]`).
  `preview.png` is that panel plus the bar strip above it, with the clock
  painted over in the bar colour `srgb(18,18,18)`.
- Backend by hand: `./coingecko-fetch --coins bitcoin,ethereum --currency usd | jq .`
  A key goes in `COINGECKO_API_KEY=…`, never argv.

## Things that bit before

- CoinGecko rate-limits aggressively: a dozen requests inside a couple of
  minutes from one IP earned a 429 during development. Do not lower the 60 s
  floor on `refreshIntervalSec`, and keep test loops sparse.
- Settings arrive after the widget is created and one field at a time, so a
  refresh per change dropped the later ones while the first was in flight.
  Fetches now go through `settingsSettle` (a debounce) plus `refreshPending`;
  keep both.
- After a *hot reload* (any file change under the plugin dir) the shell
  re-injects the settings it read at shell startup, not the current
  shell.json, so the widget can show a currency or coin list that was set and
  reverted long ago. Not a plugin bug — a fresh `omarchy-restart-shell` or any
  `omarchy bar set hegjon.coingecko …` puts it right. Do not chase it in QML.
- Nerd Font codepoints: check `glyphnames.json` upstream rather than guessing
  from MDI names — several are off by one or more (`md-chart_line` is
  `f012a`, not `f0128`).

## Style

- Comments explain *why*. Formatting rules (`formatNumber`, currency
  prefix/suffix, `changeColor` using `urgent` for down and no invented green)
  are deliberate; read them before "simplifying".
- Version lives in `manifest.json` and the `USER_AGENT` in `coingecko-fetch`.
