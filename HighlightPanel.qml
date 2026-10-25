import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The badge's menu: pick the colour that lights the badge and the focused
// monitor's current workspace, for the current theme only. A picker (shade
// square, hue strip, hex field) sets a custom colour; the buttons below pick
// one of the theme's own colours instead. The choice lives in the host
// widget (BarWidget.qml), which saves it per theme.
Panel {
  id: root
  moduleName: "vladgabrielboca.monitor-workspaces"
  manageIpc: false

  property var anchorItem: null
  // The bar identifies popouts by the widget in its slot, so the host stands
  // in for this panel everywhere the bar looks.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var choice: hostWidget ? hostWidget.highlightChoice : Model.highlightFor({}, "")
  readonly property color shownColor: hostWidget ? hostWidget.highlightColor : Commons.Color.accent
  readonly property string shownHex: Model.normalizeHex(String(shownColor))
  readonly property bool themeSet: hostWidget ? hostWidget.highlights[hostWidget.themeName] !== undefined : false

  readonly property var options: [
    { mode: "accent", label: strings.t("highlight.accent", "Accent"), tip: strings.t("highlight.accent.tip", "The theme's accent colour") },
    { mode: "alert", label: strings.t("highlight.alert", "Alert"), tip: strings.t("highlight.alert.tip", "The colour the bar uses for alerts (recording, updates)") },
    { mode: "border", label: strings.t("highlight.border", "Border"), tip: strings.t("highlight.border.tip", "The focused window's border colour") },
    { mode: "plain", label: strings.t("highlight.plain", "Plain"), tip: strings.t("highlight.plain.tip", "No colour: the unfocused bar is dimmed instead") },
    { mode: "custom", label: strings.t("highlight.custom", "Custom"), tip: strings.t("highlight.custom.tip", "Your own colour from the picker or hex field") }
  ]

  // The picker's position. Hue is kept apart from the shown colour so a grey
  // or black (which has no hue) doesn't snap the strip back to red.
  property real hue: 0
  property real saturation: 0
  property real value: 0
  property bool dragging: false

  function syncPicker() {
    if (dragging) return
    var hsv = Model.hexToHsv(shownHex)
    if (hsv.s > 0 && hsv.v > 0) hue = hsv.h
    saturation = hsv.s
    value = hsv.v
  }

  onShownHexChanged: syncPicker()
  Component.onCompleted: syncPicker()

  function pickColour() {
    if (hostWidget) hostWidget.setHighlight("custom", Model.hsvToHex(hue, saturation, value))
  }

  function choose(mode) {
    if (!hostWidget) return
    // Custom with nothing saved yet starts from the colour on screen.
    if (mode === "custom") hostWidget.setHighlight("custom", choice.hex || shownHex)
    else hostWidget.setHighlight(mode)
  }

  function optionColor(mode) {
    if (!hostWidget) return foreground
    if (mode === "custom") return choice.hex || shownHex
    return hostWidget.presetColor(mode)
  }

  function stepOption(delta) {
    var index = -1
    for (var i = 0; i < options.length; i++) if (options[i].mode === choice.mode) index = i
    index = (index + delta + options.length) % options.length
    choose(options[index].mode)
  }

  function open() {
    syncPicker()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: hexField.activeFocus
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.stepOption(dx) }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: title.implicitHeight

          Text {
            id: title
            anchors.left: parent.left
            text: strings.t("highlight.title", "Highlight colour")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.baseline: title.baseline
            anchors.left: title.right
            anchors.leftMargin: Style.space(10)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: root.hostWidget ? Model.themeTitle(root.hostWidget.themeName) : ""
            textFormat: Text.PlainText
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Shade square: saturation left to right, brightness top to bottom.
        Item {
          id: shade
          width: parent.width
          height: Style.space(150)

          Rectangle {
            anchors.fill: parent
            color: Qt.hsva(root.hue, 1, 1, 1)
          }
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "#ffffffff" }
              GradientStop { position: 1; color: "#00ffffff" }
            }
          }
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop { position: 0; color: "#00000000" }
              GradientStop { position: 1; color: "#ff000000" }
            }
          }

          Rectangle {
            readonly property real size: Style.space(12)
            x: Math.round(root.saturation * shade.width - size / 2)
            y: Math.round((1 - root.value) * shade.height - size / 2)
            width: size
            height: size
            color: "transparent"
            border.width: Style.space(2)
            border.color: root.value > 0.6 && root.saturation < 0.4 ? "#000000" : "#ffffff"
          }

          MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.CrossCursor
            function pick(mouse) {
              root.saturation = Math.min(Math.max(mouse.x / width, 0), 1)
              root.value = 1 - Math.min(Math.max(mouse.y / height, 0), 1)
              root.pickColour()
            }
            onPressed: function(mouse) { root.dragging = true; pick(mouse) }
            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
            onReleased: root.dragging = false
            onCanceled: root.dragging = false
          }
        }

        // Hue strip.
        Item {
          id: hueStrip
          width: parent.width
          height: Style.space(14)

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0 / 6; color: "#ff0000" }
              GradientStop { position: 1 / 6; color: "#ffff00" }
              GradientStop { position: 2 / 6; color: "#00ff00" }
              GradientStop { position: 3 / 6; color: "#00ffff" }
              GradientStop { position: 4 / 6; color: "#0000ff" }
              GradientStop { position: 5 / 6; color: "#ff00ff" }
              GradientStop { position: 6 / 6; color: "#ff0000" }
            }
          }

          Rectangle {
            readonly property real size: Style.space(6)
            x: Math.round(root.hue * hueStrip.width - size / 2)
            y: -Style.space(2)
            width: size
            height: hueStrip.height + Style.space(4)
            color: "transparent"
            border.width: Style.space(2)
            border.color: "#ffffff"
          }

          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -Style.space(4)
            anchors.bottomMargin: -Style.space(4)
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function pick(mouse) {
              root.hue = Math.min(Math.max(mouse.x / width, 0), 0.9999)
              root.pickColour()
            }
            onPressed: function(mouse) { root.dragging = true; pick(mouse) }
            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
            onReleased: root.dragging = false
            onCanceled: root.dragging = false
          }
        }

        // Swatch and hex field.
        Row {
          width: parent.width
          spacing: Style.space(8)

          Rectangle {
            width: hexField.height
            height: hexField.height
            color: root.shownColor
            border.width: Style.space(1)
            border.color: Util.alpha(root.foreground, 0.25)
          }

          TextField {
            id: hexField
            width: parent.width - hexField.height - parent.spacing
            foreground: root.foreground
            font.family: root.fontFamily
            placeholderText: strings.t("highlight.hex", "Hex colour")
            maximumLength: 7
            validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
            text: root.shownHex

            function commit() {
              var hex = Model.normalizeHex(text)
              if (hex !== "" && hex !== root.shownHex) root.hostWidget.setHighlight("custom", hex)
              text = Qt.binding(function() { return root.shownHex })
            }
            onAccepted: { commit(); keyCatcher.forceActiveFocus() }
            onEditingFinished: commit()
            Keys.onEscapePressed: {
              text = Qt.binding(function() { return root.shownHex })
              keyCatcher.forceActiveFocus()
            }
          }
        }

        // The theme's own colours, plus Custom. Straight-edged on purpose.
        Row {
          id: optionRow
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.options

            Rectangle {
              id: option
              required property var modelData
              readonly property bool selected: root.choice.mode === modelData.mode
              readonly property bool hot: optionMouse.containsMouse

              width: (optionRow.width - optionRow.spacing * (root.options.length - 1)) / root.options.length
              height: optionLabel.implicitHeight + Style.space(18)
              radius: 0
              color: selected ? Util.alpha(root.foreground, 0.12) : (hot ? Util.alpha(root.foreground, 0.06) : "transparent")
              border.width: Style.space(1)
              border.color: Util.alpha(root.foreground, selected ? 0.9 : (hot ? 0.45 : 0.2))

              Text {
                id: optionLabel
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Style.space(2)
                text: option.modelData.label
                color: root.foreground
                opacity: option.selected || option.hot ? 1 : 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // What this option would light the bar with, in this theme.
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(4)
                height: Style.space(3)
                color: root.optionColor(option.modelData.mode)
              }

              MouseArea {
                id: optionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.choose(option.modelData.mode)
              }

              PanelToolTip {
                visible: optionMouse.containsMouse
                text: option.modelData.tip
              }
            }
          }
        }

        Text {
          anchors.right: parent.right
          visible: root.themeSet
          text: strings.t("highlight.reset", "Reset to theme default")
          color: root.foreground
          opacity: resetMouse.containsMouse ? 1 : 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: resetMouse.containsMouse

          MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.hostWidget.setHighlight(null)
          }
        }
      }
    }
  }
}
