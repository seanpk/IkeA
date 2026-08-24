function ipcClass(toplevel) {
  var ipc = (toplevel && toplevel.lastIpcObject) || {}
  return String(ipc.class || ipc.initialClass || "")
}

function shouldSkip(toplevel) {
  if (!toplevel) return true
  var ipc = toplevel.lastIpcObject || {}
  if (ipc.hidden === true) return true
  if (ipc.mapped === false) return true
  var className = ipcClass(toplevel)
  var skip = {
    "xwaylandvideobridge": true,
    "xdg-desktop-portal-gtk": true
  }
  return skip[className.toLowerCase()] === true
}

function prettyApp(className, appId, desktopName) {
  if (desktopName) return desktopName
  var raw = String(className || appId || "App")
  var last = raw.split(".").pop()
  last = last.replace(/-/g, " ").replace(/_/g, " ")
  if (!last) return "App"
  return last.charAt(0).toUpperCase() + last.slice(1)
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
    var ws = t.workspace
    out.push({
      address: String(t.address || ""),
      title: title,
      className: className,
      appId: appId || className,
      workspaceId: ws && ws.id ? ws.id : 0,
      activated: t.activated === true,
      urgent: t.urgent === true
    })
  }
  out.sort(function(a, b) {
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

function matchesFilter(row, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  var blob = [row.prettyName, row.title, row.className, row.appId, "ws" + row.workspaceId].join(" ").toLowerCase()
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

if (typeof module !== "undefined") {
  module.exports = {
    collectWindows: collectWindows,
    matchesFilter: matchesFilter,
    prettyApp: prettyApp,
    findToplevel: findToplevel,
    windowCount: windowCount
  }
}
