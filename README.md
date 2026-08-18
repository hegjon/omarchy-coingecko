# CoinGecko for Omarchy

Cryptocurrency prices from [CoinGecko](https://www.coingecko.com/) in the
[Omarchy](https://omarchy.org/) bar.

- A live ticker on the bar: `BTC $64.6k ▲0.5%` for your first coin, every
  coin you follow, or just an icon.
- A popup with price, 1h / 24h / 7d change, market cap and rank for each coin.
  Click a coin to open its CoinGecko page; press `R` to refresh.
- Any of CoinGecko's quote currencies (`usd`, `eur`, `nok`, `btc`, …).
- No account needed. An optional free Demo API key raises the rate limit.

## Install

```bash
git clone https://github.com/hegjon/omarchy-coingecko \
  ~/.config/omarchy/plugins/hegjon.coingecko
omarchy bar put hegjon.coingecko
```

The shell picks up the new plugin without a restart. If it does not, run
`omarchy restart shell`.

## Settings

Change them from the bar's widget settings, or with `omarchy bar set`:

```bash
omarchy bar set hegjon.coingecko coins "bitcoin,ethereum,solana"
omarchy bar set hegjon.coingecko currency eur
omarchy bar set hegjon.coingecko barDisplay "All coins"
omarchy bar set hegjon.coingecko showChangeInBar false --json
```

| Key                  | Default            | Meaning                                                             |
|----------------------|--------------------|---------------------------------------------------------------------|
| `coins`              | `bitcoin,ethereum` | Comma-separated CoinGecko ids. The first is the one on the bar.     |
| `currency`           | `usd`              | Quote currency code.                                                |
| `barDisplay`         | `First coin`       | `First coin`, `All coins` or `Icon only`.                           |
| `showChangeInBar`    | `true`             | Append the 24h change to the ticker.                                |
| `compactPrices`      | `true`             | `64.6k` instead of `64,568` on the bar. The popup is never compact. |
| `refreshIntervalSec` | `120`              | Poll interval, 60–3600 s.                                           |
| `apiKey`             | *(empty)*          | CoinGecko Demo API key, sent as `x-cg-demo-api-key`.                |

Coin ids are the slug in a coin's CoinGecko URL: `coingecko.com/en/coins/solana`
→ `solana`. Ids the API does not know are listed in the popup rather than
silently dropped.

## Rate limits

CoinGecko's public endpoint allows roughly 5–15 requests a minute per IP and
serves prices cached for about a minute, so the widget polls no faster than
every 60 s and defaults to 120 s. When CoinGecko answers 429, the popup says so
and the last known prices stay on screen; a longer interval or a
[free Demo key](https://www.coingecko.com/en/developers/dashboard) is the fix.

## IPC

```bash
omarchy-shell hegjon.coingecko open|close|toggle|refresh
```

## How it works

`coingecko-fetch` does the one HTTP request (`/coins/markets`) with `curl` and
normalizes the answer with `jq` (`normalize.jq`); the widget (`CoingeckoWidget.qml`) only ever
runs that script and renders its JSON. The API key travels in the environment,
never on the command line.

## Development

`test/lint` runs `qmllint` with the shell's modules on the import path;
`test/test-normalize` exercises `normalize.jq` against the fixtures under
`test/fixtures/`; `test/test-manifest` checks `manifest.json` against the
shell's rules, and `omarchy plugin validate .` is the authority on an Omarchy
machine. CI (`.github/workflows/ci.yml`) runs the hermetic subset: manifest,
shellcheck and normalization.

## License

MIT — see `LICENSE`. Data is provided by CoinGecko under their
[terms](https://www.coingecko.com/en/api_terms).
