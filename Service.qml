import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property string state: "starting"
  property double managedPid: 0
  property bool processAlive: false
  property bool windowMoved: false
  property bool windowMovePending: false
  property double windowDeadline: 0
  property bool launcherReportedPid: false
  property string pendingSpecialAction: ""
  property string afterToggle: ""

  readonly property var settings: {
    var config = shell && shell.shellConfig
    var entries = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && entries[i].id === "omaclip.scratchpad") return entries[i]
    }
    return ({})
  }
  readonly property string executable: String(settings.executable || "omaclip")
  readonly property string processName: executable.split("/").pop()
  readonly property string mdnsInterface: String(settings.mdnsInterface || "")
  readonly property string scratchpad: String(settings.scratchpad || "scratchpad")
  readonly property int clipboardMaxHistory: Math.max(1, Number(settings.clipboardMaxHistory || 100))
  readonly property int pasteDelayMs: Math.max(0, Number(settings.pasteDelayMs || 200))
  readonly property bool remoteClipboardsDisabled: settings.remoteClipboardsDisable === true || String(settings.remoteClipboardsDisable).toLowerCase() === "true"
  readonly property string copyHookArgument: "--copy-hook=omarchy-shell omaclip copied"
  function appendConfigured(command, settingName, flagName) {
    if (settings[settingName] === undefined || settings[settingName] === null) return
    var value = settings[settingName]
    if (Array.isArray(value)) value = value.join(";")
    if (String(value) === "") return
    command.push("--" + flagName + "=" + String(value))
  }
  readonly property var omaclipCommand: {
    var command = [
      executable,
      copyHookArgument,
      "--clipboard-max-history=" + clipboardMaxHistory
    ]
    appendConfigured(command, "clipboardMaxNonPngImageMB", "clipboard-max-non-png-image-mb")
    appendConfigured(command, "clipboardMaxPinned", "clipboard-max-pinned")
    appendConfigured(command, "clipboardMaxPngImageMB", "clipboard-max-png-image-mb")
    appendConfigured(command, "clipboardPollInterval", "clipboard-poll-interval")
    appendConfigured(command, "configPath", "config-path")
    appendConfigured(command, "debug", "debug")
    appendConfigured(command, "peersList", "peers-list")
    appendConfigured(command, "peersPollInterval", "peers-poll-interval")
    appendConfigured(command, "remoteClipboardsDisable", "remote-clipboards-disable")
    appendConfigured(command, "remoteClipboardsMaxHistory", "remote-clipboards-max-history")
    appendConfigured(command, "remoteClipboardsPollInterval", "remote-clipboards-poll-interval")
    appendConfigured(command, "syncServerPort", "sync-server-port")
    appendConfigured(command, "themeColorPath", "theme-color-path")
    return command
  }

  function checkReadiness() {
    if (managedPid > 0 || readinessProbe.running || launcher.running) return
    state = "waiting"
    readinessProbe.running = true
  }

  function handleReadiness(result) {
    if (result.indexOf("adopt:") === 0) {
      beginTracking(Number(result.substring(6)))
      return
    }
    if (result === "ready" || result.indexOf("ready:") === 0) {
      var interfaceName = result.indexOf("ready:") === 0 ? result.substring(6) : mdnsInterface
      startOmaclip(interfaceName)
      return
    }
    state = result === "external" ? "external-instance" : "waiting"
    readinessRetry.restart()
  }

  function startOmaclip(interfaceName) {
    if (managedPid > 0 || launcher.running) return
    state = "launching"
    launcherReportedPid = false
    var command = [
      "bash",
      "-c",
      "setsid \"$@\" >/dev/null 2>&1 & printf '%s\\n' \"$!\"",
      "omaclip-launch"
    ]
    var launchCommand = omaclipCommand.slice()
    if (interfaceName !== "") launchCommand.push("--peers-mdns-interface=" + interfaceName)
    launcher.command = command.concat(launchCommand)
    launcher.running = true
  }

  function handleLaunchedPid(text) {
    var pid = Number(String(text).trim())
    if (!isFinite(pid) || pid <= 0) return
    launcherReportedPid = true
    beginTracking(pid)
  }

  function beginTracking(pid) {
    if (!isFinite(pid) || pid <= 0) {
      readinessRetry.restart()
      return
    }
    managedPid = pid
    processAlive = true
    windowMoved = false
    windowMovePending = false
    state = "locating-window"
    windowDeadline = Date.now() + 15000
    windowProbe.interval = 250
    windowProbe.start()
    processMonitor.start()
  }

  function loseTrackedProcess() {
    managedPid = 0
    processAlive = false
    windowMoved = false
    windowMovePending = false
    state = "stopped"
    windowProbe.stop()
    processMonitor.stop()
    processRetry.restart()
  }

  function inspectClients(text) {
    if (managedPid <= 0 || windowMoved || windowMovePending) return

    try {
      var clients = JSON.parse(text)
      for (var i = 0; i < clients.length; i++) {
        if (Number(clients[i].pid) !== managedPid) continue
        windowMovePending = true
        windowProbe.stop()
        moveWindow.command = [
          "hyprctl",
          "dispatch",
          "hl.dsp.window.move({ workspace = \"special:" + scratchpad + "\", follow = false, window = \"pid:" + managedPid + "\" })"
        ]
        moveWindow.running = true
        return
      }
    } catch (error) {
      console.warn("Omaclip service could not parse Hyprland clients:", error)
    }
  }

  function requestSpecialAction(action) {
    if (pendingSpecialAction !== "" || specialStateProbe.running || toggleScratchpad.running || focusDelay.running || focusOmaclip.running || pasteDelay.running || paste.running) return "busy"
    pendingSpecialAction = action
    specialStateProbe.running = true
    return "ok"
  }

  function inspectSpecialState(text) {
    var visible = false
    try {
      var monitors = JSON.parse(text)
      for (var i = 0; i < monitors.length; i++) {
        var special = monitors[i].specialWorkspace
        if (special && String(special.name) === "special:" + scratchpad) {
          visible = true
          break
        }
      }
    } catch (error) {
      console.warn("Omaclip service could not parse Hyprland monitors:", error)
      pendingSpecialAction = ""
      return
    }

    var action = pendingSpecialAction
    pendingSpecialAction = ""
    if (action === "copied") {
      if (visible) runScratchpadToggle("paste")
      else pasteDelay.restart()
      return
    }
    if (action === "toggle") {
      runScratchpadToggle(visible ? "" : "focus")
    }
  }

  function runScratchpadToggle(nextAction) {
    afterToggle = nextAction
    toggleScratchpad.command = ["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"" + scratchpad + "\")"]
    toggleScratchpad.running = true
  }

  Timer {
    id: readinessRetry
    interval: 1000
    onTriggered: root.checkReadiness()
  }

  Timer {
    id: processRetry
    interval: 2000
    onTriggered: root.checkReadiness()
  }

  Process {
    id: readinessProbe
    command: [
      "bash",
      "-c",
      "name=\"$1\"; hook=\"$2\"; interface=\"$3\"; remote_disabled=\"$4\"; for pid in $(pgrep -x \"$name\" 2>/dev/null); do if tr '\\0' '\\n' < \"/proc/$pid/cmdline\" 2>/dev/null | grep -Fxq -- \"$hook\"; then printf 'adopt:%s\\n' \"$pid\"; exit 0; fi; done; if pgrep -x \"$name\" >/dev/null 2>&1; then echo external; exit 0; fi; if [ \"$remote_disabled\" = true ]; then echo ready; exit 0; fi; if [ -n \"$interface\" ]; then [ \"$(cat \"/sys/class/net/$interface/operstate\" 2>/dev/null)\" = up ] && ip -o -4 address show dev \"$interface\" scope global -tentative 2>/dev/null | grep -q . || { echo wait; exit 0; }; else previous=\"\"; for word in $(ip -o -4 route show default 2>/dev/null); do if [ \"$previous\" = dev ]; then interface=\"$word\"; break; fi; previous=\"$word\"; done; [ -n \"$interface\" ] && [ \"$(cat \"/sys/class/net/$interface/operstate\" 2>/dev/null)\" = up ] && ip -o -4 address show dev \"$interface\" scope global -tentative 2>/dev/null | grep -q . || { echo wait; exit 0; }; fi; printf 'ready:%s\\n' \"$interface\"",
      "omaclip-readiness",
      root.processName,
      root.copyHookArgument,
      root.mdnsInterface,
      root.remoteClipboardsDisabled ? "true" : "false"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleReadiness(String(text).trim())
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) readinessRetry.restart()
    }
  }

  Process {
    id: launcher
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleLaunchedPid(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.launcherReportedPid) {
        root.state = "launch-failed"
        readinessRetry.restart()
      }
    }
  }

  Timer {
    id: processMonitor
    interval: 2000
    repeat: true
    onTriggered: {
      if (root.managedPid > 0 && !lifeProbe.running) {
        lifeProbe.command = ["bash", "-c", "kill -0 \"$1\" 2>/dev/null", "omaclip-alive", String(root.managedPid)]
        lifeProbe.running = true
      }
    }
  }

  Process {
    id: lifeProbe
    onExited: function(exitCode) {
      if (exitCode !== 0) root.loseTrackedProcess()
    }
  }

  Timer {
    id: windowProbe
    interval: 250
    repeat: true
    onTriggered: {
      if (Date.now() >= root.windowDeadline && interval !== 2000) {
        interval = 2000
        root.state = "waiting-for-window"
      }
      if (!clientProbe.running) clientProbe.running = true
    }
  }

  Process {
    id: clientProbe
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.inspectClients(text)
    }
  }

  Process {
    id: moveWindow
    onExited: function(exitCode) {
      root.windowMovePending = false
      if (exitCode === 0) {
        root.windowMoved = true
        root.state = "running"
      } else {
        root.state = "move-failed"
        root.windowDeadline = 0
        windowProbe.interval = 2000
        windowProbe.start()
        console.warn("Omaclip window move failed with code", exitCode)
      }
    }
  }

  Process {
    id: specialStateProbe
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.inspectSpecialState(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.pendingSpecialAction = ""
    }
  }

  Process {
    id: toggleScratchpad
    onExited: function(exitCode) {
      var nextAction = root.afterToggle
      root.afterToggle = ""
      if (exitCode !== 0) {
        console.warn("Omaclip scratchpad toggle failed with code", exitCode)
        return
      }
      if (nextAction === "focus") focusDelay.restart()
      else if (nextAction === "paste") pasteDelay.restart()
    }
  }

  Timer {
    id: focusDelay
    interval: 50
    onTriggered: {
      if (root.managedPid <= 0) return
      focusOmaclip.command = ["hyprctl", "dispatch", "hl.dsp.focus({ window = \"pid:" + root.managedPid + "\" })"]
      focusOmaclip.running = true
    }
  }

  Process {
    id: focusOmaclip
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("Omaclip focus failed with code", exitCode)
    }
  }

  Timer {
    id: pasteDelay
    interval: root.pasteDelayMs
    onTriggered: paste.running = true
  }

  Process {
    id: paste
    command: ["wtype", "-M", "ctrl", "-M", "shift", "-P", "v", "-p", "v", "-m", "shift", "-m", "ctrl"]
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("Omaclip paste failed with code", exitCode)
    }
  }

  IpcHandler {
    target: "omaclip"

    function copied(): string {
      return root.requestSpecialAction("copied")
    }

    function toggle(): string {
      if (root.managedPid <= 0 || !root.processAlive) return "unavailable"
      return root.requestSpecialAction("toggle")
    }

    function status(): string {
      return JSON.stringify({
        state: root.state,
        running: root.processAlive,
        processId: root.managedPid > 0 ? root.managedPid : null,
        windowMoved: root.windowMoved,
        command: root.omaclipCommand,
        mdnsInterface: root.mdnsInterface,
        scratchpad: root.scratchpad
      })
    }
  }

  Component.onCompleted: checkReadiness()
}
