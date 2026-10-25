import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// One widget, two looks, chosen by the `display` setting:
//   Workspaces    - the workspaces this bar's monitor owns, numbered 1..N
//   Monitor badge - a monitor glyph lit on the focused monitor's bar; clicking
//                   it opens the highlight colour menu (HighlightPanel.qml)
// Each monitor owns a block of ten real workspaces. With Omarchy's built-in
// per-monitor workspaces, the blocks are the ones Omarchy assigns and keeps in
// ~/.local/state/omarchy/monitor-workspaces; without it, monitors ordered left
// to right own them, as hypr/monitor-workspaces.lua does.
BarWidget {
  id: root
  moduleName: "vladgabrielboca.monitor-workspaces"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property bool badgeMode: root.setting("display", "Workspaces") === "Monitor badge"

  readonly property var window: root.QsWindow.window
  readonly property var monitor: window && window.screen ? Hyprland.monitorFor(window.screen) : null
  readonly property string monitorName: monitor ? monitor.name : ""
  readonly property bool monitorFocused: monitor !== null && Hyprland.focusedMonitor === monitor
  readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1

  // Omarchy's engine is present when its module is installed; its blocks come
  // from the state file it writes, by connector name.
  property bool builtin: false
  property var blocks: ({})

  FileView {
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/hypr/monitor-workspaces.lua"
    printErrors: false
    onLoaded: root.builtin = true
    onLoadFailed: root.builtin = false
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.blocks = Model.parseBlocks(text())
    onLoadFailed: root.blocks = ({})
  }

  readonly property int first: {
    if (root.builtin) return Model.builtinFirst(root.blocks, root.monitorName, root.activeId)
    var monitors = []
    var values = Hyprland.monitors.values
    for (var i = 0; i < values.length; i++) {
      var ipc = values[i].lastIpcObject || {}
      monitors.push({
        name: values[i].name,
        x: values[i].x,
        y: values[i].y,
        mirror: ipc.mirrorOf !== undefined && ipc.mirrorOf !== "none"
      })
    }
    return Model.firstWorkspace(monitors, root.monitorName)
  }

  readonly property var ids: {
    var existing = []
    var guests = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      existing.push(values[i].id)
      if (root.monitor && values[i].monitor === root.monitor) guests.push(values[i].id)
    }
    return Model.visibleIds(root.first, existing, guests)
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    var slot = id - root.first + 1
    // Omarchy's own focus action also pulls a workspace of this monitor's block
    // back from wherever it wandered.
    var expression = root.builtin && slot >= 1 && slot <= Model.BLOCK
      ? "o.workspaces.focus(" + slot + ", \"" + Model.plain(root.monitorName) + "\")"
      : "hl.dsp.focus({ workspace = \"" + id + "\" })"
    root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  // ---- Highlight colour: what lights the badge and the current workspace.
  // Every widget instance, on every bar, reads the same per-theme file, so a
  // change made in one bar's menu shows on all of them.
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  property string themeName: "default"
  property var highlights: ({})
  readonly property var highlightChoice: Model.highlightFor(root.highlights, root.themeName)

  function presetColor(mode) {
    if (mode === "alert") return root.bar ? root.bar.urgent : Commons.Color.bar.active
    if (mode === "plain") return root.bar ? root.bar.barForeground : Commons.Color.foreground
    if (mode === "border") {
      // The focused window's border; a gradient gives its first stop.
      var c = Commons.Color.composed("hyprland.active-border", "hyprland.active-border-alpha", Commons.Color.accent, 1.0)
      return Qt.rgba(c.r, c.g, c.b, 1)
    }
    return Commons.Color.accent
  }

  readonly property color highlightColor: root.highlightChoice.mode === "custom"
    ? root.highlightChoice.hex
    : root.presetColor(root.highlightChoice.mode)

  // `mode` null forgets this theme's choice. Writes while dragging the picker
  // go out at most every 80 ms, so the other bars follow along live.
  function setHighlight(mode, hex) {
    root.highlights = Model.withHighlight(root.highlights, root.themeName, mode, hex)
    if (!saveTimer.running) saveTimer.start()
  }

  Timer {
    id: saveTimer
    interval: 80
    onTriggered: highlightFile.setText(JSON.stringify(root.highlights, null, 2) + "\n")
  }

  FileView {
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeName = text().replace(/^\s+|\s+$/g, "") || "default"
    onLoadFailed: root.themeName = "default"
  }

  FileView {
    id: highlightFile
    path: root.stateHome + "/vladgabrielboca.monitor-workspaces/highlight.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    // A write of ours still waiting to go out is newer than what's on disk.
    onLoaded: if (!saveTimer.running) root.highlights = Model.parseHighlights(text())
    onLoadFailed: if (!saveTimer.running) root.highlights = ({})
  }

  // ---- The menu. Shape contract for the bar's popout routing: open, close
  // and opened on the bar-widget root, which stands in for the panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = badge
    target.hostWidget = root
  }

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: root.badgeMode
    source: Qt.resolvedUrl("HighlightPanel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }

  // Monitor positions come from Hyprland's monitor list, which Quickshell
  // only refreshes on request; a layout change or hotplug asks for it again.
  // Quickshell also misses which monitor a moved workspace landed on and a
  // workspace that changed number (Omarchy's engine renumbers on unplug), so
  // those ask Hyprland too.
  Component.onCompleted: Hyprland.refreshMonitors()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded" || name === "monitoraddedv2" || name === "monitorremovedv2") {
        Hyprland.refreshMonitors()
      } else if (name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  readonly property real trailingGap: root.vertical || root.badgeMode ? 0 : Style.spaceReal(1.5)

  implicitWidth: (root.badgeMode ? badge.implicitWidth : grid.implicitWidth) + trailingGap
  implicitHeight: root.badgeMode ? badge.implicitHeight : grid.implicitHeight

  WidgetButton {
    id: badge
    visible: root.badgeMode
    anchors.centerIn: parent
    bar: root.bar
    text: "󰍹"
    active: root.monitorFocused
    dimmed: !root.monitorFocused
    centerFigures: false
    fixedHeight: root.barSize
    activeColor: root.highlightColor
    tooltipText: root.opened ? "" : (root.monitorFocused
      ? strings.t("badge.focused", "%1 has focus").arg(Model.plain(root.monitorName))
      : strings.t("badge.unfocused", "%1 (Super+Tab to focus)").arg(Model.plain(root.monitorName)))
    onPressed: function() { root.togglePanel() }
  }

  GridLayout {
    id: grid
    visible: !root.badgeMode
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.ids.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.badgeMode ? [] : root.ids

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.monitor === root.monitor
          && workspace.toplevels.values.length > 0
        readonly property bool shown: root.activeId === modelData

        bar: root.bar
        text: Model.slotLabel(root.first, modelData)
        // The workspace showing on this monitor is lit only while the monitor
        // has focus, so SUPER + 1..5 lands on the bar whose number is lit.
        active: shown && root.monitorFocused
        activeColor: root.highlightColor
        opacity: shown || occupied ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
