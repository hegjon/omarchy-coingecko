pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// One coin in the list: name and symbol, price, and the change over 1h/24h/7d
// with market cap and rank underneath. Clicking the row opens the coin's
// CoinGecko page.
//
// `host` is the widget root, which owns the formatting helpers and the theme
// colours; the row itself keeps no state beyond what it is given.
Item {
  id: row

  required property var coin
  required property var host

  signal activated()

  implicitHeight: content.implicitHeight + Style.space(8)

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.space(6)
    anchors.rightMargin: -Style.space(6)
    radius: Style.space(6)
    color: Color.popups.text
    opacity: mouse.containsMouse ? 0.08 : 0
    Behavior on opacity { NumberAnimation { duration: 100 } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.activated()
  }

  Column {
    id: content
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        id: nameText
        width: parent.width - priceText.implicitWidth - Style.space(8)
        elide: Text.ElideRight
        text: row.coin.name
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        id: priceText
        text: row.host.formatPrice(row.coin.price, false)
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width - changeRow.implicitWidth - Style.space(8)
        elide: Text.ElideRight
        text: row.coin.symbol
          + (row.coin.rank ? "  ·  #" + row.coin.rank : "")
          + (row.coin.marketCap ? "  ·  " + row.host.formatBig(row.coin.marketCap) : "")
        color: row.host.detailColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      // 1h · 24h · 7d, each coloured by its own sign; the 24h figure is the
      // one the bar shows, so it is the one set in the readable weight.
      Row {
        id: changeRow
        spacing: Style.space(6)

        Text {
          text: "1h " + row.host.formatChange(row.coin.change1h)
          color: row.host.changeColor(row.coin.change1h)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          text: "24h " + row.host.formatChange(row.coin.change24h)
          color: row.host.changeColor(row.coin.change24h)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          text: "7d " + row.host.formatChange(row.coin.change7d)
          color: row.host.changeColor(row.coin.change7d)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
