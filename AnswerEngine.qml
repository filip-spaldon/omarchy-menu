import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "MenuModel.js" as MenuModel

// Instant answers: the searches that answer themselves -- arithmetic,
// currency and unit conversion, time zones, generated values (uuid,
// password, epoch...), killing a process, opening a URL, running a shell
// command, and the web search offered when nothing else matched. Each
// builder turns a query into rows (see queryRows for the order they are
// tried in); the data some of them need -- exchange rates, randomness, the
// process list, zone offsets -- is fetched here, lazily and bounded. What a
// picked row does is Menu.qml's (activateIndex).
Item {
  id: answers

  required property var menu

  property bool currencyCacheRead: false

  // Currency conversion typed into the search: "123 eur to usd". The rates
  // behind it are exchangerate-api's free daily snapshot, which needs no key,
  // cached under ~/.cache and refetched about once a day.
  readonly property string currencyRatesUrl: "https://open.er-api.com/v6/latest/EUR"

  readonly property string currencyRatesPath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omarchy/menu-exchange-rates.json"

  property var currencyRates: null

  property bool currencyFetchFailed: false

  property real currencyFetchedAt: 0

  // Randomness for the rows that make some. Math.random is not something to
  // build a password out of, so bytes come from /dev/urandom in bulk and are
  // drawn down from a pool; a row that needs more than is left says so and
  // waits rather than making do with less.
  property var randomPool: []

  property real randomFetchedAt: 0

  // A generated answer must not change while the query that asked for it is
  // still being typed, so each is kept against the query that produced it --
  // and thrown away when the menu closes, so the next one is new.
  property var utilityAnswers: ({})

  // The last `ps` listing, and when it was taken.
  property string processList: ""

  property real processListedAt: 0

  // The system's zone database, borrowed rather than reimplemented: the zone
  // list from timedatectl, and each zone's current offset from `date`. The
  // engine QML runs has no Intl, so the offset is what the clock is built on.
  property var timeZones: []

  property var zoneOffsets: ({})

  property real localZoneOffset: 0

  // Where a search that matched nothing gets offered.
  //
  // By default the engine is not chosen here at all: the query is handed to
  // the browser behind a "?", which is what its own address bar treats as
  // "search with the configured engine". So the menu follows whatever is set
  // in the browser, including a later change to it, and no template here has
  // to be kept in step. Chromium-family browsers understand the prefix from
  // the command line; Firefox does not, and takes the template below instead.
  //
  // Set to false to always use webSearchTemplate.
  readonly property bool webSearchUsesBrowserDefault: true

  // The fallback, and what a `false` above selects. A template rather than a
  // base URL, so swapping engines stays one line however that engine spells
  // its parameters.
  readonly property string webSearchTemplate: "https://duckduckgo.com/?q={query}"

  readonly property string webSearchName: "DuckDuckGo"

  // Keywords whose answer is a fresh draw rather than a function of what was
  // typed. Only these are offered a reroll: running sha256 over the same
  // argument again returns the same digest, and a shortcut that visibly does
  // nothing is worse than no shortcut.
  readonly property var regenerableUtilities: ["uuid", "password", "epoch"]

  // The self-answering searches, in the order they get asked. Each builder
  // takes the query and returns a row, a list of rows, or null for a query it
  // does not recognise; the first one that recognises it wins.
  //
  // Order settles the overlaps. Arithmetic goes first because it is the
  // strictest grammar. Currency goes before units so that "100 cup to eur" is
  // the Cuban peso, while units still take "2 cup to ml" -- currency declines
  // it, since "ml" is not money.
  function queryRows(query) {
    var builders = [
      answers.shellRow,
      answers.calculatorRow,
      answers.currencyRow,
      answers.unitRow,
      answers.timeRow,
      answers.utilityRow,
      answers.urlRow,
      answers.killRows
    ]

    for (var i = 0; i < builders.length; i++) {
      var produced = null
      // These parse whatever was typed, and a throw in one of them would
      // otherwise take the whole result list down with it -- the search would
      // go blank rather than lose a row. Log it and carry on without it.
      try {
        produced = builders[i](query)
      } catch (e) {
        console.warn("omarchy.menu: query row builder failed:", e)
        continue
      }

      if (!produced) continue
      var list = (produced instanceof Array) ? produced : [produced]
      if (list.length > 0) return list
    }

    return []
  }

  // A search that reads as arithmetic answers itself. Nothing in the menu
  // matches "2+3", so without this the query that most obviously has an answer
  // is the one that comes back empty; the result leads the list, and Enter
  // copies it, which is the whole of what a calculator is wanted for here.
  function calculatorRow(query) {
    var result = MenuModel.evaluateMath(query)
    if (!result) return null

    return answers.menu.queryRow({
      kind: "calc",
      icon: "󰃬",
      label: result,
      detail: "Copy to clipboard"
    })
  }

  // Currency's twin, answered from a table that ships with the plugin: no
  // network, no cache, and an answer on the first keystroke that completes the
  // query. A pair is only a unit conversion when both sides measure the same
  // thing, which is what keeps it from arguing with the currency table.
  function unitRow(query) {
    var parsed = MenuModel.parseUnitQuery(query)
    if (!parsed) return null

    var converted = MenuModel.convertUnit(parsed)
    if (!converted) return null

    var asked = MenuModel.formatMathResult(parsed.amount) + " " + parsed.from.symbol
    // Temperature scales disagree about zero, so there is no ratio between
    // them to show and the row just restates what was asked.
    var detail = converted.rate
      ? asked + " at " + MenuModel.formatUnitValue(converted.rate)
      : asked

    return answers.menu.queryRow({
      kind: "unit",
      icon: "󰓡",
      label: MenuModel.formatUnitValue(converted.value) + " " + parsed.to.symbol,
      detail: detail,
      payload: MenuModel.formatUnitValue(converted.value)
    })
  }

  // The small answers a terminal usually gets opened for. A keyword and the
  // rest of the line; the answer leads the list and Enter copies it.
  function utilityRow(query) {
    var parsed = MenuModel.parseUtilityQuery(query)
    if (!parsed) return null

    var answer = answers.utilityAnswer(query, parsed)
    if (!answer) return null

    if (answer === "pending") {
      return answers.menu.queryRow({
        kind: "util",
        icon: "󰅴",
        label: parsed.keyword,
        detail: "Gathering randomness…",
        ready: false
      })
    }

    return answers.menu.queryRow({
      kind: "util",
      icon: "󰅴",
      label: answer.label,
      // A reroll is only discoverable if the row says so.
      detail: answers.regenerableQuery() ? answer.detail + " · Ctrl+R for another" : answer.detail,
      payload: answer.copy
    })
  }

  // The current query when it is a draw worth repeating, "" otherwise.
  function regenerableQuery() {
    var query = answers.menu.answerQuery
    if (!query) return ""
    var parsed = MenuModel.parseUtilityQuery(query)
    if (!parsed || answers.regenerableUtilities.indexOf(parsed.keyword) < 0) return ""
    // `epoch <value>` reads back the value it was given; only a bare `epoch`
    // is the clock, and worth asking again.
    if (parsed.keyword === "epoch" && parsed.argument) return ""
    return query
  }

  // Forget this query's answer and let the row builder draw another. The map
  // is replaced rather than written into: an in-place write into a QML `var`
  // object is occasionally dropped by the engine.
  function regenerateUtility() {
    var query = answers.regenerableQuery()
    if (!query) return false

    var next = ({})
    for (var key in answers.utilityAnswers)
      if (key !== query) next[key] = answers.utilityAnswers[key]
    answers.utilityAnswers = next

    answers.menu.rebuildDisplay()
    return true
  }

  function utilityAnswer(query, parsed) {
    if (Object.prototype.hasOwnProperty.call(answers.utilityAnswers, query))
      return answers.utilityAnswers[query]

    var answer = answers.computeUtility(parsed)
    // A row still waiting on /dev/urandom has no answer to remember yet.
    if (answer === "pending") return answer

    answers.utilityAnswers[query] = answer
    return answer
  }

  // Returns the answer, "pending" while the randomness for it is still being
  // read, or null for a keyword that was given nothing to work on -- which
  // leaves "base64" on its own an ordinary search.
  function computeUtility(parsed) {
    var argument = parsed.argument
    var keyword = parsed.keyword

    if (keyword === "uuid") {
      if (argument) return null
      if (!answers.ensureRandomBytes(16)) return "pending"
      var uuid = MenuModel.uuidFromBytes(answers.takeRandomBytes(16))
      return { label: uuid, detail: "Random UUID v4", copy: uuid }
    }

    if (keyword === "password") {
      var length = argument ? parseInt(argument, 10) : 20
      if (!(length > 0)) return null
      length = Math.min(length, 64)
      // Three bytes per character leaves room for the ones rejection sampling
      // throws away, with plenty of margin.
      var needed = length * 3
      if (!answers.ensureRandomBytes(needed)) return "pending"
      var password = MenuModel.passwordFromBytes(answers.takeRandomBytes(needed), length)
      if (!password) return "pending"
      return { label: password, detail: length + " random characters", copy: password }
    }

    if (keyword === "base64" || keyword === "b64") {
      if (!argument) return null
      var encoded = MenuModel.base64Encode(argument)
      return { label: encoded, detail: "base64 of “" + argument + "”", copy: encoded }
    }

    if (keyword === "b64d" || keyword === "unbase64") {
      if (!argument) return null
      var decoded = MenuModel.base64Decode(argument)
      if (!decoded) return null
      return { label: decoded, detail: "Decoded from base64", copy: decoded }
    }

    if (keyword === "urlencode") {
      if (!argument) return null
      var escaped = encodeURIComponent(argument)
      return { label: escaped, detail: "Percent-encoded", copy: escaped }
    }

    if (keyword === "urldecode") {
      if (!argument) return null
      var unescaped = ""
      try { unescaped = decodeURIComponent(argument) } catch (e) { return null }
      return { label: unescaped, detail: "Percent-decoded", copy: unescaped }
    }

    if (keyword === "sha256") {
      if (!argument) return null
      var digest = MenuModel.sha256Hex(argument)
      return { label: digest, detail: "SHA-256 of “" + argument + "”", copy: digest }
    }

    if (keyword === "epoch") {
      if (!argument) {
        var now = String(Math.floor(Date.now() / 1000))
        return {
          label: now,
          detail: "Seconds since 1970 · " + Qt.formatDateTime(new Date(), "d MMM HH:mm:ss"),
          copy: now
        }
      }
      var milliseconds = MenuModel.epochMilliseconds(argument)
      if (milliseconds === null) return null
      var when = Qt.formatDateTime(new Date(milliseconds), "ddd d MMM yyyy HH:mm:ss")
      return { label: when, detail: "Local time for " + argument, copy: when }
    }

    return null
  }

  // True when the pool can already cover `needed`. When it cannot, one read of
  // /dev/urandom is started and the answer waits for it.
  function ensureRandomBytes(needed) {
    if (answers.randomPool.length >= needed) return true
    if (randomProc.running) return false

    var now = Math.floor(Date.now() / 1000)
    // Every keystroke asks, so a read that failed must not be retried by the
    // next character typed.
    if (now - answers.randomFetchedAt < 5) return false
    answers.randomFetchedAt = now

    randomProc.command = answers.menu.boundedCommand("od -An -v -tu1 -N 1024 /dev/urandom", 5, 16384)
    randomProc.running = true
    return false
  }

  function takeRandomBytes(count) {
    if (answers.randomPool.length < count) return null

    var taken = answers.randomPool.slice(0, count)
    answers.randomPool = answers.randomPool.slice(count)
    // Top up before the pool is empty, so the next answer does not have to
    // wait on a read that could have happened already.
    if (answers.randomPool.length < 256) answers.ensureRandomBytes(1024)
    return taken
  }

  // The one search that answers with a list rather than a single row. `ps` is
  // the same answer whoever is asking, so it is run once and filtered here --
  // no listing per keystroke, and none at all until "kill" is typed.
  function killRows(query) {
    var filter = MenuModel.parseKillQuery(query)
    if (filter === null) return null

    answers.ensureProcessList()

    if (!answers.processList) {
      return [answers.menu.queryRow({
        kind: "kill", icon: "󰚌",
        label: filter, detail: "Listing processes…", ready: false
      })]
    }

    var found = MenuModel.parseProcessList(answers.processList, filter, 8)
    if (found.length === 0) {
      return [answers.menu.queryRow({
        kind: "kill", icon: "󰚌",
        label: filter, detail: "No process by that name", ready: false
      })]
    }

    var rows = []
    for (var i = 0; i < found.length; i++) {
      rows.push(answers.menu.queryRow({
        id: "kill." + found[i].pid,
        kind: "kill",
        icon: "󰚌",
        label: found[i].name,
        detail: "pid " + found[i].pid + " · " + found[i].cpu.toFixed(1)
              + "% cpu · " + MenuModel.formatMemory(found[i].rss),
        payload: String(found[i].pid)
      }))
    }

    return rows
  }

  // Held for a few seconds rather than debounced: the listing is what is
  // expensive, and one that is seconds old is still the right answer to
  // "what is called firefox".
  function ensureProcessList() {
    if (processProc.running) return

    var now = Math.floor(Date.now() / 1000)
    if (answers.processList && now - answers.processListedAt < 5) return
    answers.processListedAt = now

    processProc.command = answers.menu.boundedCommand("ps -eo pid,comm,pcpu,rss --sort=-pcpu --no-headers", 5, 262144)
    processProc.running = true
  }

  // "time in tokyo". Two things have to be fetched before this can answer --
  // the zone list once, then the zone's offset -- and each one that is missing
  // shows as a row that says so rather than as nothing at all.
  function timeRow(query) {
    var place = MenuModel.parseTimeQuery(query)
    if (place === null) return null

    if (!answers.ensureTimeZones()) return answers.timePendingRow(place)

    var zone = MenuModel.resolveZone(place, answers.timeZones)
    // Not a place the system has heard of. Fall through, so "now playing"
    // stays an ordinary search.
    if (!zone) return null

    if (!answers.ensureZoneOffset(zone)) return answers.timePendingRow(place)

    var offset = answers.zoneOffsets[zone].offset
    var there = MenuModel.zoneClock(Date.now(), offset)
    var here = MenuModel.zoneClock(Date.now(), answers.localZoneOffset)
    // The day only earns a place on the line when it is not today's.
    var sameDay = there.date === here.date && there.month === here.month && there.year === here.year
    var weekday = MenuModel.zoneWeekdayName(there.weekday).slice(0, 3)

    return answers.menu.queryRow({
      kind: "time",
      icon: "󰅐",
      label: sameDay ? there.time : there.time + " " + weekday,
      detail: zone + " · " + MenuModel.zoneDifference(offset, answers.localZoneOffset),
      payload: there.time
    })
  }

  function timePendingRow(place) {
    return answers.menu.queryRow({
      kind: "time",
      icon: "󰅐",
      label: place,
      detail: "Reading the zone database…",
      ready: false
    })
  }

  function ensureTimeZones() {
    if (answers.timeZones.length > 0) return true
    if (!zoneListProc.running) zoneListProc.running = true
    return false
  }

  // Offsets are re-read after half an hour. They only move when a zone enters
  // or leaves summer time, and a shell that has been up for a week should not
  // still be an hour out because of it.
  function ensureZoneOffset(zone) {
    var known = answers.zoneOffsets[zone]
    var now = Math.floor(Date.now() / 1000)
    if (known && now - known.readAt < 1800) return true
    if (zoneOffsetProc.running) return false

    zoneOffsetProc.zone = zone
    zoneOffsetProc.command = answers.menu.boundedCommand(
      "TZ=" + Util.shellQuote(zone) + " date +%z; date +%z", 5, 256)
    zoneOffsetProc.running = true
    return false
  }

  // A pasted link opens rather than matching nothing. Recognising one is
  // deliberately conservative -- see parseUrlQuery -- because "MenuModel.js"
  // gets typed into this field more often than a link to Moldova.
  function urlRow(query) {
    var link = MenuModel.parseUrlQuery(query)
    if (!link) return null

    // The link itself on the top line: it is the part worth reading, and the
    // card is narrow enough that a leading "Open " pushes the end of it out.
    return answers.menu.queryRow({
      kind: "url",
      icon: "󰖟",
      label: link.display,
      detail: "Open in browser",
      payload: link.url
    })
  }

  // The last resort, and the reason the menu no longer dead-ends: a search
  // that matched nothing at all is offered to the web instead. Appended rather
  // than returned by queryRows, so it can never crowd out a real answer.
  function webSearchRow(query) {
    var text = String(query || "").trim()
    if (!text) return null

    // "? <query>" is not a URL, and openUrl() hands it over quoted, so the
    // browser receives it as the single argument its address bar would.
    var payload = answers.webSearchUsesBrowserDefault
      ? "? " + text
      : MenuModel.webSearchUrl(text, answers.webSearchTemplate)
    if (!payload) return null

    // The query is already on the line above, so the row says what will
    // happen to it rather than repeating it back.
    return answers.menu.queryRow({
      kind: "websearch",
      icon: "󰍉",
      label: "Search the web",
      detail: answers.webSearchUsesBrowserDefault
        ? "Look up “" + text + "” in your browser"
        : "Look up “" + text + "” on " + answers.webSearchName,
      payload: payload
    })
  }

  // The other search that answers itself, give or take a table of rates. Same
  // shape as the calculator row, except the answer lives on a server: the
  // first conversion anyone types asks for the rates and stands in for the
  // answer until they land, and every one after it reads the cached snapshot.
  function currencyRow(query) {
    var parsed = MenuModel.parseCurrencyQuery(query)
    if (!parsed) return null

    answers.ensureCurrencyRates()

    var snapshot = answers.currencyRates
    var converted = snapshot ? MenuModel.convertCurrency(parsed, snapshot.rates) : null
    var asked = MenuModel.formatMathResult(parsed.amount) + " " + parsed.from
    var label = ""
    var detail = ""

    if (converted) {
      label = MenuModel.formatCurrencyValue(converted.value) + " " + parsed.to
      // Terse because the row is one line of a narrow card: what was asked,
      // the rate it went through, and how old that rate is.
      detail = asked + " at " + MenuModel.formatCurrencyRate(converted.rate)
      var asOf = answers.currencyRatesDate()
      if (asOf) detail += " · " + asOf
    } else {
      label = asked + " → " + parsed.to
      if (!snapshot)
        detail = answers.currencyFetchFailed ? "Exchange rates unavailable" : "Fetching exchange rates…"
      else
        detail = "No rate for " + (snapshot.rates[parsed.from] ? parsed.to : parsed.from)
    }

    return answers.menu.queryRow({
      kind: "currency",
      icon: "󰄔",
      label: label,
      detail: detail,
      payload: converted ? MenuModel.formatCurrencyValue(converted.value) : "",
      ready: !!converted
    })
  }

  // The date the snapshot was published, which is the honest thing to put
  // next to a rate that is up to a day old.
  function currencyRatesDate() {
    var snapshot = answers.currencyRates
    if (!snapshot) return ""
    if (snapshot.updated > 0) return Qt.formatDate(new Date(snapshot.updated * 1000), "d MMM")
    return snapshot.date || ""
  }

  // Fetched on demand -- the first conversion someone types -- so a menu never
  // used as a converter never reaches the network, and one that is reaches it
  // about as often as the rates change. Written to a temporary name and moved
  // into place so a fetch cut off halfway cannot leave half a snapshot behind.
  function ensureCurrencyRates() {
    if (currencyRatesProc.running || currencyCacheProc.running) return

    // The cache is read on the first conversion typed rather than at startup,
    // so a menu never used as a converter never touches the file at all. Its
    // collector rebuilds the row, which comes back through here to decide
    // whether what it found is still current.
    if (!answers.currencyCacheRead) {
      answers.currencyCacheRead = true
      answers.loadCurrencyCache()
      return
    }

    var now = Math.floor(Date.now() / 1000)
    if (!MenuModel.currencyRatesStale(answers.currencyRates, now)) return
    // Every keystroke of a conversion comes through here, so a fetch that
    // failed has to stay failed for a while rather than be retried by the
    // next character typed.
    if (now - answers.currencyFetchedAt < 60) return
    answers.currencyFetchedAt = now

    var target = answers.currencyRatesPath
    var directory = target.substring(0, target.lastIndexOf("/"))

    // Nothing here writes to a name anyone could have guessed. mktemp creates
    // with O_EXCL and mode 600, so a pre-placed file or symlink at the
    // temporary path makes the fetch fail rather than redirect it; the cache
    // directory is checked to be ours and not writable by anyone else before
    // that; curl is capped so a source that answers with gigabytes cannot fill
    // the disk; and the move is a rename, which replaces a symlink sitting at
    // the target instead of writing through it.
    var script = [
      'set -u',
      'd=' + Util.shellQuote(directory),
      't=',
      'cleanup() { [ -n "$t" ] && rm -f -- "$t"; }',
      'trap cleanup EXIT',
      'mkdir -p -m 700 -- "$d" 2>/dev/null',
      // A directory that is a symlink, or belongs to someone else, or that
      // anyone can write to, cannot hold a cache worth trusting.
      'if [ -L "$d" ] || [ ! -d "$d" ]; then exit 1; fi',
      'find "$d" -maxdepth 0 -uid "$(id -u)" ! -perm /022 -print -quit 2>/dev/null | grep -q . || exit 1',
      't=$(mktemp -- "$d/.rates.XXXXXXXXXXXX") || exit 1',
      'curl -fsS --max-time 8 --max-filesize ' + answers.menu.currencyFileCeiling
        + ' -o "$t" -- ' + Util.shellQuote(answers.currencyRatesUrl) + ' || exit 1',
      // curl only enforces --max-filesize against a declared length, so a
      // chunked reply is measured here before it is kept.
      '[ "$(wc -c < "$t")" -le ' + answers.menu.currencyFileCeiling + ' ] || exit 1',
      'mv -f -- "$t" ' + Util.shellQuote(target) + ' || exit 1',
      't='
    ].join("\n")

    currencyRatesProc.command = ["bash", "-c", script]
    currencyRatesProc.running = true
  }

  // "shell <command>": run it in a new terminal. The command is the user's
  // own, typed on purpose, so it runs as written -- but it reaches bash as a
  // positional argument (eval "$1"), never spliced into the script, and the
  // terminal drops into an interactive shell afterwards so the output stays
  // readable (ping sme.sk, then Ctrl+C, and the window is still there).
  function shellRow(query) {
    var match = String(query || "").match(/^shell\s+([\s\S]+)$/i)
    if (!match) return null
    var command = match[1].trim()
    if (!command) return null
    return answers.menu.queryRow({
      kind: "shell",
      icon: "󰆍",
      label: command,
      detail: "Run in a new terminal",
      payload: command
    })
  }

  function loadCurrencyCache() {
    if (currencyCacheProc.running) return
    currencyCacheProc.command = answers.menu.readFileCommand(answers.currencyRatesPath, answers.menu.currencyFileCeiling)
    currencyCacheProc.running = true
  }

  Process {
    id: zoneListProc
    command: answers.menu.boundedCommand("timedatectl list-timezones", 5, 65536)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var zones = String(text || "").split("\n")
        var kept = []
        for (var i = 0; i < zones.length; i++) {
          var zone = zones[i].trim()
          if (zone) kept.push(zone)
        }
        if (kept.length === 0) return

        answers.timeZones = kept
        if (answers.menu.filterText.trim()) answers.menu.rebuildDisplay()
      }
    }
  }

  Process {
    id: zoneOffsetProc
    property string zone: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var offset = MenuModel.parseZoneOffset(lines[0])
        var local = lines.length > 1 ? MenuModel.parseZoneOffset(lines[1]) : null
        if (offset === null) return

        if (local !== null) answers.localZoneOffset = local
        var next = answers.zoneOffsets
        next[zoneOffsetProc.zone] = { offset: offset, readAt: Math.floor(Date.now() / 1000) }
        answers.zoneOffsets = next
        if (answers.menu.filterText.trim()) answers.menu.rebuildDisplay()
      }
    }
  }

  Process {
    id: processProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        answers.processList = String(text || "")
        if (answers.menu.filterText.trim()) answers.menu.rebuildDisplay()
      }
    }
  }

  Process {
    id: randomProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split(/\s+/)
        var bytes = []
        for (var i = 0; i < parts.length; i++) {
          if (!parts[i]) continue
          var value = parseInt(parts[i], 10)
          if (value >= 0 && value <= 255) bytes.push(value)
        }
        if (bytes.length === 0) return

        answers.randomPool = answers.randomPool.concat(bytes)
        if (answers.menu.filterText.trim()) answers.menu.rebuildDisplay()
      }
    }
  }

  Process {
    id: currencyRatesProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0) {
        answers.loadCurrencyCache()
        return
      }

      // Offline, or the source is down. The row says so rather than sitting on
      // "fetching…" forever; `currencyFetchedAt` keeps the retry off the next
      // keystroke.
      answers.currencyFetchFailed = true
      if (answers.menu.filterText.trim()) answers.menu.rebuildDisplay()
    }
  }

  // The cached snapshot, which is a plain copy of what the rate source last
  // answered. Missing on a machine that has never converted anything, which is
  // what the first conversion typed goes and fixes. Read through the same
  // helper as the menu sources: the cache lives under ~/.cache, so the file at
  // that path is not necessarily the file this shell last wrote there.
  Process {
    id: currencyCacheProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var snapshot = MenuModel.parseCurrencyRates(String(text || ""))
        answers.currencyRates = snapshot
        if (snapshot) answers.currencyFetchFailed = false
        // Rebuild either way. A cache that was missing or stale leaves the row
        // to ask ensureCurrencyRates again, which is what starts the fetch.
        if (answers.menu.filterText.trim()) answers.menu.rebuildDisplay()
      }
    }
  }
}
