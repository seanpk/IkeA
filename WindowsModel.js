function ipcClass(toplevel) {
  var ipc = (toplevel && toplevel.lastIpcObject) || {}
  return String(ipc.class || ipc.initialClass || "")
}

function shouldSkip(toplevel) {
  if (!toplevel) return true
  var ipc = toplevel.lastIpcObject || {}
  if (ipc.mapped === false) return true
  var ws = workspaceInfo(toplevel)
  if (ipc.hidden === true && !isScratchpad(ws)) return true
  var className = ipcClass(toplevel)
  var skip = {
    "xwaylandvideobridge": true,
    "xdg-desktop-portal-gtk": true
  }
  return skip[className.toLowerCase()] === true
}

function prettyApp(className, appId, desktopName) {
  if (desktopName) return desktopName
  var raw = String(className || appId || "")
  var chrome = raw.match(/^chrome-(.+)__-/)
  if (chrome) {
    var host = chrome[1]
    var parts = host.split(".")
    var label = parts[0]
    if (label === "www" || label === "web" || label === "app" || label === "m")
      label = parts.length > 1 ? parts[1] : label
    if (!label) label = host
    return label.charAt(0).toUpperCase() + label.slice(1)
  }
  var info = chromeWebAppInfo(className) || chromeWebAppInfo(appId)
  if (info && info.host) return info.host
  var last = raw.split(".").pop()
  last = last.replace(/-/g, " ").replace(/_/g, " ")
  if (!last) return "App"
  return last.charAt(0).toUpperCase() + last.slice(1)
}

function browserProfile(className, appId, title) {
  var raw = String(className || appId || "")
  var tagged = raw.match(/__-([A-Za-z0-9][A-Za-z0-9 _.-]*)$/)
  if (tagged) {
    var name = tagged[1].replace(/[_-]+/g, " ").trim()
    if (name.toLowerCase() === "default") return "Default"
    return name
  }
  var t = String(title || "")
  var numbered = t.match(/\bProfile \d+\b/i)
  if (numbered) return numbered[0]
  return ""
}

function waylandFor(toplevel) {
  return toplevel && toplevel.wayland ? toplevel.wayland : null
}

function aspectRatioFor(ipc) {
  var size = (ipc && ipc.size) || []
  var width = Number(size[0])
  var height = Number(size[1])
  if (!isFinite(width) || !isFinite(height) || width <= 0 || height <= 0)
    return 1.6
  return Math.max(0.55, Math.min(2.6, width / height))
}

function workspaceInfo(toplevel) {
  var ipc = (toplevel && toplevel.lastIpcObject) || {}
  var ws = toplevel ? toplevel.workspace : null
  var ipcWs = ipc.workspace || {}
  var id = 0
  if (ws && typeof ws.id === "number") id = ws.id
  else if (typeof ipcWs.id === "number") id = ipcWs.id
  var name = ""
  if (ws && ws.name) name = String(ws.name)
  else if (ipcWs.name) name = String(ipcWs.name)
  return { id: id, name: name }
}

function isScratchpad(ws) {
  if (!ws) return false
  if (typeof ws.id === "number" && ws.id < 0) return true
  var name = String(ws.name || "").toLowerCase()
  return name.indexOf("special") === 0 || name.indexOf("scratch") !== -1
}

// Chromium --app= windows advertise
// `chrome-<host>_<path>-<profile>` (slashes in the path become `_`,
// spaces in the profile directory become `_`). Regular browser windows
// stay `chromium` on Wayland, with no per-profile app id.
function chromeWebAppInfo(className) {
  var raw = String(className || "")
  if (raw.indexOf("chrome-") !== 0) return null
  var rest = raw.slice("chrome-".length)
  var match = rest.match(/^(.*)-(Default|Profile_\d+|Guest_Profile)$/)
  if (!match) return null
  var appPart = match[1]
  if (!appPart) return null
  var host = appPart.split("_")[0]
  if (!host || host.indexOf(".") < 0) return null
  return {
    host: host,
    appPart: appPart,
    profile: match[2].replace(/_/g, " "),
    className: raw
  }
}

function hostsInExec(execString) {
  var exec = String(execString || "")
  var hosts = []
  var re = /https?:\/\/([^\/\s"'\\]+)/gi
  var m
  while ((m = re.exec(exec))) {
    var host = m[1].split(":")[0].toLowerCase()
    if (host) hosts.push(host)
  }
  return hosts
}

function execHasHost(execString, host) {
  var want = String(host || "").toLowerCase()
  if (!want) return false
  var hosts = hostsInExec(execString)
  for (var i = 0; i < hosts.length; i++) {
    if (hosts[i] === want) return true
  }
  return false
}

function profileFromExec(execString) {
  var exec = String(execString || "")
  var m = exec.match(/--profile-directory=(?:"([^"]+)"|'([^']+)'|(\S+))/)
  if (!m) return ""
  return m[1] || m[2] || m[3] || ""
}

function normalizeProfile(value) {
  return String(value || "").replace(/_/g, " ").toLowerCase()
}

// Resolve a running window to a .desktop entry.
// Prefer Quickshell's heuristicLookup (id, then StartupWMClass). Never match
// by Icon= — every Chromium profile launcher shares Icon=chromium, so that
// would label every browser window with whichever profile file came first.
function findDesktopEntry(className, appId, entries, heuristicLookup) {
  var seen = {}
  var needles = [className, appId]
  for (var i = 0; i < needles.length; i++) {
    var needle = String(needles[i] || "")
    if (!needle || seen[needle]) continue
    seen[needle] = true
    if (typeof heuristicLookup === "function") {
      var looked = heuristicLookup(needle)
      if (looked) return looked
    }
    if (!entries) continue
    var needleLower = needle.toLowerCase()
    var idHit = null
    var startupHits = []
    for (var j = 0; j < entries.length; j++) {
      var entry = entries[j]
      var id = String((entry && entry.id) || "")
      var startup = String((entry && entry.startupClass) || "")
      if (id && id.toLowerCase() === needleLower) idHit = entry
      if (startup && startup.toLowerCase() === needleLower) startupHits.push(entry)
    }
    if (idHit) return idHit
    if (startupHits.length === 1) return startupHits[0]
    for (var s = 0; s < startupHits.length; s++) {
      if (String(startupHits[s].id || "").toLowerCase() === needleLower) return startupHits[s]
    }
  }

  var info = chromeWebAppInfo(className) || chromeWebAppInfo(appId)
  if (!info || !entries) return null
  var hostBest = null
  var profileBest = null
  var infoProfile = normalizeProfile(info.profile)
  for (var k = 0; k < entries.length; k++) {
    var candidate = entries[k]
    if (!execHasHost(candidate && candidate.execString, info.host)) continue
    hostBest = candidate
    var execProfile = profileFromExec(candidate.execString)
    if (execProfile && normalizeProfile(execProfile) === infoProfile)
      profileBest = candidate
  }
  return profileBest || hostBest
}

function collectWindows(hyprland) {
  var out = []
  if (!hyprland || !hyprland.toplevels) return out
  var values = hyprland.toplevels.values || []
  for (var i = 0; i < values.length; i++) {
    var t = values[i]
    if (shouldSkip(t)) continue
    var ipc = t.lastIpcObject || {}
    var className = ipcClass(t)
    var appId = ""
    try {
      appId = t.wayland ? String(t.wayland.appId || "") : ""
    } catch (e) {
      appId = ""
    }
    if (!className) className = appId
    var title = String(t.title || ipc.title || "")
    if (!className && !title) continue
    var ws = workspaceInfo(t)
    out.push({
      address: String(t.address || ""),
      title: title,
      className: className,
      appId: appId || className,
      workspaceId: ws.id,
      workspaceName: ws.name,
      scratchpad: isScratchpad(ws),
      profileName: browserProfile(className, appId, title),
      aspectRatio: aspectRatioFor(ipc),
      activated: t.activated === true,
      urgent: t.urgent === true
    })
  }
  out.sort(function(a, b) {
    if (a.scratchpad !== b.scratchpad) return a.scratchpad ? 1 : -1
    if (a.activated !== b.activated) return a.activated ? -1 : 1
    if (a.workspaceId !== b.workspaceId) return a.workspaceId - b.workspaceId
    var an = (a.className + a.title).toLowerCase()
    var bn = (b.className + b.title).toLowerCase()
    if (an < bn) return -1
    if (an > bn) return 1
    return 0
  })
  return out
}

function partitionWindows(rows) {
  var mill = []
  var scratch = []
  for (var i = 0; i < (rows || []).length; i++) {
    if (rows[i].scratchpad) scratch.push(rows[i])
    else mill.push(rows[i])
  }
  return { mill: mill, scratch: scratch }
}

function matchesFilter(row, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  var blob = [
    row.prettyName, row.title, row.className, row.appId, row.profileName,
    "ws" + row.workspaceId, row.workspaceName,
    row.scratchpad ? "scratchpad scratch special" : ""
  ].join(" ").toLowerCase()
  return blob.indexOf(q) !== -1
}

function findToplevel(hyprland, address) {
  if (!hyprland || !hyprland.toplevels) return null
  var values = hyprland.toplevels.values || []
  var needle = String(address || "")
  for (var i = 0; i < values.length; i++) {
    if (String(values[i].address || "") === needle) return values[i]
  }
  return null
}

function windowCount(hyprland) {
  return collectWindows(hyprland).length
}

// Ctrl+1–9. index is into the focused section's already-filtered model.
function pickFilteredIndex(section, index, millCount, scratchCount) {
  if (typeof index !== "number" || index < 0 || index > 8) return -1
  var count = section === "scratch" ? scratchCount : millCount
  if (typeof count !== "number" || index >= count) return -1
  return index
}

if (typeof module !== "undefined") {
  module.exports = {
    collectWindows: collectWindows,
    partitionWindows: partitionWindows,
    matchesFilter: matchesFilter,
    prettyApp: prettyApp,
    chromeWebAppInfo: chromeWebAppInfo,
    hostsInExec: hostsInExec,
    execHasHost: execHasHost,
    profileFromExec: profileFromExec,
    findDesktopEntry: findDesktopEntry,
    findToplevel: findToplevel,
    windowCount: windowCount,
    isScratchpad: isScratchpad,
    workspaceInfo: workspaceInfo,
    browserProfile: browserProfile,
    waylandFor: waylandFor,
    aspectRatioFor: aspectRatioFor,
    pickFilteredIndex: pickFilteredIndex
  }
}
