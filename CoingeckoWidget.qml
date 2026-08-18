pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "./components"

// Bar ticker and popup for cryptocurrency prices from CoinGecko.
//
// All network work happens in coingecko-fetch, which prints a normalized model
// on stdout and reports failures as {"error":…} rather than dying, so the panel
// can always render a reason.
Panel {
  id: root

  readonly property string pluginId: "hegjon.coingecko"

  moduleName: pluginId
  ipcTarget: pluginId

  // --- state ------------------------------------------------------------

  property var coins: []
  property var missing: []
  property string currency: "usd"
  property string lastError: ""
  property bool initialized: false
  property bool refreshing: false
  property real lastUpdatedAt: 0

  // --- settings ---------------------------------------------------------

  // `omarchy bar set` stores booleans as strings unless given --json, so a
  // boolean setting has to be coerced rather than read straight through.
  function boolSetting(key, fallback) {
    var value = settings ? settings[key] : undefined
    if (value === undefined || value === null) return fallback
    if (typeof value === "string") return value !== "false" && value !== "0" && value !== ""
    return value !== false
  }

  function intSetting(key, fallback, min, max) {
    var value = parseInt(setting(key, fallback), 10)
    if (!isFinite(value)) return fallback
    return Math.max(min, Math.min(max, value))
  }

  readonly property string coinIds: String(setting("coins", "bitcoin,solana,monero,stellar,bitcoin-cash")).trim()
  readonly property string currencySetting: String(setting("currency", "USD")).trim().toLowerCase()
  readonly property string barDisplay: String(setting("barDisplay", "First coin"))
  readonly property string panelSort: String(setting("panelSort", "Market cap"))
  readonly property bool showChangeInBar: boolSetting("showChangeInBar", true)
  readonly property bool compactPrices: boolSetting("compactPrices", true)
  readonly property int refreshIntervalMs: intSetting("refreshIntervalSec", 300, 60, 3600) * 1000
  readonly property string apiKey: String(setting("apiKey", "")).trim()

  readonly property bool iconOnly: barDisplay === "Icon only"
  readonly property bool allCoinsInBar: barDisplay === "All coins"

  // Qt.resolvedUrl yields a file:// URL; Process wants a plain path.
  readonly property string backendPath:
    Qt.resolvedUrl("coingecko-fetch").toString().replace(/^file:\/\//, "")

  readonly property string chartGlyph: String.fromCodePoint(0xF012A)   // nf-md-chart_line
  readonly property string upGlyph: "▲"
  readonly property string downGlyph: "▼"

  // A change of settings that alters what is fetched should be visible at once
  // rather than after the next scheduled poll. The refresh is debounced: the
  // bar injects settings shortly after the widget is created, and a user
  // editing several fields lands them one at a time, so fetching on every
  // change would spend rate limit on requests whose answer is discarded.
  onCoinIdsChanged: settingsSettle.restart()
  onCurrencySettingChanged: settingsSettle.restart()
  onApiKeyChanged: settingsSettle.restart()

  Timer {
    id: settingsSettle
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  // The first poll goes through the same debounce, so it sees the injected
  // settings rather than the manifest defaults.
  Component.onCompleted: settingsSettle.restart()

  // --- formatting -------------------------------------------------------

  // Secondary text. See the note in the first-party panels: `Color.muted` is
  // not guaranteed readable, so dim the popup foreground instead.
  readonly property color detailColor:
    Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.75)

  // The quote currency's symbol where one is customary; the upper-case code
  // otherwise. Prefixed symbols are the ones a reader expects glued to the
  // number; the rest go after it with a space, as "1 234 kr" does.
  function currencyPrefix(code) {
    switch (code) {
      case "usd": case "aud": case "cad": case "nzd": case "sgd": case "hkd": case "mxn": return "$"
      case "eur": return "€"
      case "gbp": return "£"
      case "jpy": case "cny": return "¥"
      case "inr": return "₹"
      case "krw": return "₩"
      case "btc": return "₿"
      case "eth": return "Ξ"
      default: return ""
    }
  }

  function currencySuffix(code) {
    switch (code) {
      case "nok": case "sek": case "dkk": return " kr"
      case "chf": return " CHF"
      case "pln": return " zł"
      case "czk": return " Kč"
      default: return currencyPrefix(code) === "" ? " " + code.toUpperCase() : ""
    }
  }

  // Digits only, sized to the magnitude: whole units above 1000, cents above 1,
  // and enough significant figures for micro-cap coins to say anything at all.
  function formatNumber(value) {
    if (value === null || value === undefined || !isFinite(value)) return "--"
    var abs = Math.abs(value)
    if (abs >= 1000) return Number(value.toFixed(0)).toLocaleString(Qt.locale(), "f", 0)
    if (abs >= 1) return value.toFixed(2)
    if (abs >= 0.01) return value.toFixed(4)
    if (abs === 0) return "0"
    return Number(value.toPrecision(3)).toString()
  }

  // Bar version: "64.5k" rather than "64,543", because the bar has no room and
  // the trend is what a glance wants anyway.
  function formatCompactNumber(value) {
    if (value === null || value === undefined || !isFinite(value)) return "--"
    var abs = Math.abs(value)
    if (abs >= 1e9) return (value / 1e9).toFixed(2) + "B"
    if (abs >= 1e6) return (value / 1e6).toFixed(2) + "M"
    if (abs >= 1e4) return (value / 1e3).toFixed(1) + "k"
    return formatNumber(value)
  }

  function formatPrice(value, compact) {
    var digits = compact ? formatCompactNumber(value) : formatNumber(value)
    if (digits === "--") return digits
    return currencyPrefix(currency) + digits + currencySuffix(currency)
  }

  // Market caps and volumes are only ever read as magnitudes.
  function formatBig(value) {
    if (value === null || value === undefined || !isFinite(value)) return "--"
    var abs = Math.abs(value)
    var digits
    if (abs >= 1e12) digits = (value / 1e12).toFixed(2) + "T"
    else if (abs >= 1e9) digits = (value / 1e9).toFixed(2) + "B"
    else if (abs >= 1e6) digits = (value / 1e6).toFixed(1) + "M"
    else if (abs >= 1e3) digits = (value / 1e3).toFixed(0) + "k"
    else digits = value.toFixed(0)
    return currencyPrefix(currency) + digits + currencySuffix(currency)
  }

  function formatChange(value) {
    if (value === null || value === undefined || !isFinite(value)) return "--"
    var glyph = value > 0 ? upGlyph : (value < 0 ? downGlyph : "")
    return glyph + Math.abs(value).toFixed(value !== 0 && Math.abs(value) < 0.1 ? 2 : 1) + "%"
  }

  // Up is the popup text colour rather than an invented green: themes define
  // no "good" colour, and urgent is the one signal colour every theme has, so
  // it marks the direction that costs money.
  function changeColor(value) {
    if (value === null || value === undefined || !isFinite(value)) return detailColor
    if (value < 0) return Color.urgent
    return Color.popups.text
  }

  function formatAgo(epochSeconds) {
    if (!epochSeconds) return "never"
    var deltaSeconds = nowMs / 1000 - epochSeconds
    if (deltaSeconds < 90) return "just now"
    if (deltaSeconds < 3600) return Math.round(deltaSeconds / 60) + " min ago"
    if (deltaSeconds < 86400) return Math.round(deltaSeconds / 3600) + " h ago"
    return Math.round(deltaSeconds / 86400) + " d ago"
  }

  function coinUrl(coin) {
    return "https://www.coingecko.com/en/coins/" + encodeURIComponent(coin.id)
  }

  function openCoin(coin) {
    if (!coin || !bar) return
    bar.run("omarchy-launch-browser " + Util.shellQuote(coinUrl(coin)))
    close()
  }

  // Re-evaluated on a timer: a binding on Date.now() alone would never update,
  // because nothing notifies it that time has passed.
  property real nowMs: 0

  // A failed poll keeps the last prices in the panel next to an "Updated 20 min
  // ago" line, which is honest. The bar has no room for a qualifier, so a
  // number older than three polls is dropped rather than shown as current.
  readonly property bool dataIsStale: {
    if (lastUpdatedAt <= 0) return true
    return (nowMs - lastUpdatedAt) > refreshIntervalMs * 3
  }

  // The popup's order. `coins` itself stays in configured order because the
  // bar shows its first entry, so the sort is a separate view of the same
  // list. Coins the API gave no figure for sink to the bottom rather than
  // sorting as zero.
  readonly property var panelCoins: {
    if (panelSort === "Configured order") return coins
    var key = panelSort === "24h change"
      ? function(c) { return c.change24h }
      : function(c) { return c.marketCap }
    var sorted = coins.slice()
    sorted.sort(function(a, b) {
      var ka = key(a), kb = key(b)
      var aMissing = ka === null || ka === undefined || !isFinite(ka)
      var bMissing = kb === null || kb === undefined || !isFinite(kb)
      if (aMissing && bMissing) return 0
      if (aMissing) return 1
      if (bMissing) return -1
      return kb - ka
    })
    return sorted
  }

  function tickerFor(coin) {
    var text = coin.symbol + " " + formatPrice(coin.price, compactPrices)
    if (showChangeInBar && coin.change24h !== null && coin.change24h !== undefined)
      text += " " + formatChange(coin.change24h)
    return text
  }

  readonly property string barText: {
    if (iconOnly) return ""
    if (!initialized || coins.length === 0 || dataIsStale) return ""
    if (allCoinsInBar) return coins.map(tickerFor).join("   ")
    return tickerFor(coins[0])
  }

  readonly property string tooltipSummary: {
    if (lastError !== "") return "CoinGecko: " + lastError
    if (!initialized) return "CoinGecko: loading…"
    if (coins.length === 0) return "CoinGecko: no coins"
    var lines = []
    for (var i = 0; i < coins.length; i++) {
      var coin = coins[i]
      lines.push(coin.symbol + " " + formatPrice(coin.price, false)
        + "  " + formatChange(coin.change24h))
    }
    return lines.join("\n")
  }

  // Panel's own IpcHandler is replaced so that `refresh` can sit next to
  // open/close/toggle under the one target the plugin already publishes.
  manageIpc: false

  IpcHandler {
    target: root.pluginId

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  // --- fetching ---------------------------------------------------------

  // A refresh asked for while one is in flight is remembered rather than
  // dropped: changing currency and coins back to back would otherwise leave
  // the second change unapplied until the next scheduled poll.
  property bool refreshPending: false

  function refresh() {
    if (fetchProcess.running) { refreshPending = true; return }
    refreshPending = false
    refreshing = true
    fetchProcess.command = [backendPath, "--coins", coinIds, "--currency", currencySetting]
    // The key travels in the environment rather than argv so it never shows
    // up in `ps` or the journal.
    fetchProcess.environment = apiKey !== "" ? ({ COINGECKO_API_KEY: apiKey }) : ({})
    fetchProcess.running = true
  }

  function applyOutput(text) {
    refreshing = false
    initialized = true

    var parsed
    try {
      parsed = JSON.parse(String(text || ""))
    } catch (error) {
      lastError = "The CoinGecko helper returned something unreadable"
      return
    }

    if (parsed && parsed.error) {
      lastError = String(parsed.error)
      console.warn("coingecko: poll failed:", lastError)
      return
    }

    lastError = ""
    coins = (parsed && parsed.coins) ? parsed.coins : []
    missing = (parsed && parsed.missing) ? parsed.missing : []
    if (parsed && parsed.currency) currency = String(parsed.currency)
    lastUpdatedAt = Date.now()
  }

  Process {
    id: fetchProcess
    running: false
    command: []

    stdout: StdioCollector { id: fetchStdout; waitForEnd: true }
    stderr: StdioCollector { id: fetchStderr; waitForEnd: true }

    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.applyOutput(fetchStdout.text)
      } else {
        root.refreshing = false
        root.initialized = true
        var detail = String(fetchStderr.text || "").replace(/\s+/g, " ").trim()
        root.lastError = detail !== ""
          ? detail
          : "The CoinGecko helper exited with code " + exitCode
      }
      if (root.refreshPending) Qt.callLater(root.refresh)
    }
  }

  Timer {
    interval: root.refreshIntervalMs
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    // Drives dataIsStale and the "Updated … ago" line. Independent of the
    // poll timer so a wedged poll cannot also freeze the staleness check.
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  // Opening the panel is a request for current numbers, unless the last poll
  // is fresh enough that a second request would only spend rate limit.
  onOpenedChanged: if (opened && (Date.now() - lastUpdatedAt) > 30000) refresh()

  // --- bar button -------------------------------------------------------

  implicitWidth: root.iconOnly || root.barText === "" ? iconButton.implicitWidth : textButton.implicitWidth
  implicitHeight: root.iconOnly || root.barText === "" ? iconButton.implicitHeight : textButton.implicitHeight

  Item {
    id: buttonHost
    anchors.fill: parent

    // Icon while nothing is worth saying (icon-only mode, loading, an error,
    // stale data); a text ticker otherwise.
    BarIconButton {
      id: iconButton
      anchors.fill: parent
      visible: root.iconOnly || root.barText === ""
      bar: root.bar
      text: root.chartGlyph
      dimmed: root.lastError !== "" || (!root.iconOnly && root.initialized && root.coins.length === 0)
      active: root.lastError !== ""
      activeColor: Color.urgent
      tooltipText: root.tooltipSummary
      slotSize: Style.bar.statusSlot

      onPressed: function(buttonCode) {
        if (buttonCode === Qt.MiddleButton) root.refresh()
        else root.toggle()
      }
    }

    WidgetButton {
      id: textButton
      anchors.fill: parent
      visible: !iconButton.visible
      bar: root.bar
      text: root.barText
      tooltipText: root.tooltipSummary
      horizontalMargin: 8.75

      onPressed: function(buttonCode) {
        if (buttonCode === Qt.MiddleButton) root.refresh()
        else root.toggle()
      }
    }
  }

  // --- popup ------------------------------------------------------------

  KeyboardPanel {
    id: pricePanel
    anchorItem: buttonHost
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: pricePanel.fittedContentWidth(Style.space(360))
    contentHeight: pricePanel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // One action per press: a held key would otherwise refetch every repeat.
      property string heldKey: ""
      Keys.onReleased: function(event) { if (!event.isAutoRepeat) keyCatcher.heldKey = "" }
      onTextKey: function(text) {
        var key = text.toLowerCase()
        if (heldKey === key) return
        heldKey = key
        if (key === "r") root.refresh()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width

          PanelSectionHeader {
            width: parent.width - currencyLabel.implicitWidth
            text: "CoinGecko"
          }

          Text {
            id: currencyLabel
            text: root.currency.toUpperCase()
            color: root.detailColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.lastError !== ""
          text: root.lastError
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          visible: !root.initialized && root.lastError === ""
          text: "Loading…"
          color: root.detailColor
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.initialized && root.lastError === "" && root.coins.length === 0
          text: root.missing.length > 0
            ? "CoinGecko does not know any of: " + root.missing.join(", ")
              + ". Use the ids from the coin's CoinGecko page URL."
            : "No coins configured. Set some CoinGecko ids in the widget settings."
          color: root.detailColor
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.panelCoins

          CoinRow {
            id: coinEntry

            required property var modelData

            width: column.width
            coin: coinEntry.modelData
            host: root
            onActivated: root.openCoin(coinEntry.modelData)
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.coins.length > 0 && root.missing.length > 0
          text: "Unknown coin id" + (root.missing.length > 1 ? "s" : "") + ": " + root.missing.join(", ")
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          text: root.refreshing
            ? "Refreshing…"
            : (root.lastUpdatedAt > 0
               ? "Updated " + root.formatAgo(root.lastUpdatedAt / 1000) + "   ·   R to refresh"
               : "")
          color: root.detailColor
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
