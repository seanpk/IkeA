// Behaviour tests for WindowsModel.js. Run with: node test/test_windows_model.js

const assert = require("assert")
const M = require("../WindowsModel.js")

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (error) {
    console.error("FAIL: " + name)
    console.error("      " + error.message)
    process.exitCode = 1
  }
}

const ENTRIES = [
  { id: "chromium", name: "Chromium", icon: "chromium", startupClass: "chromium", execString: "/usr/bin/chromium %U" },
  { id: "chromium-simbiotrek", name: "Chromium — Simbiotrek", icon: "chromium", startupClass: "chromium", execString: '/usr/bin/chromium --profile-directory=Default %U' },
  { id: "chromium-rolemodel", name: "Chromium — RoleModel", icon: "chromium", startupClass: "chromium", execString: '/usr/bin/chromium --profile-directory="Profile 1" %U' },
  { id: "chromium-personal", name: "Chromium — Personal", icon: "chromium", startupClass: "chromium", execString: '/usr/bin/chromium --profile-directory="Profile 2" %U' },
  { id: "Harvest", name: "Harvest", icon: "harvest", startupClass: "chrome-rolemodelsoftware.harvestapp.com__time-Profile_1", execString: 'omarchy-launch-webapp --profile-directory="Profile 1" https://rolemodelsoftware.harvestapp.com/time' },
  { id: "Basecamp", name: "Basecamp", icon: "basecamp", startupClass: "chrome-launchpad.37signals.com__-Default", execString: "omarchy-launch-webapp https://launchpad.37signals.com" }
]

function byIdLookup(name) {
  var needle = String(name || "").toLowerCase()
  for (var i = 0; i < ENTRIES.length; i++) {
    if (String(ENTRIES[i].id).toLowerCase() === needle) return ENTRIES[i]
  }
  return null
}

// -------------------------------------------------------------- chromeWebAppInfo

test("chromeWebAppInfo parses a Default-profile app window", () => {
  const info = M.chromeWebAppInfo("chrome-launchpad.37signals.com__-Default")
  assert.equal(info.host, "launchpad.37signals.com")
  assert.equal(info.profile, "Default")
})

test("chromeWebAppInfo parses a numbered profile and path", () => {
  const info = M.chromeWebAppInfo("chrome-rolemodelsoftware.harvestapp.com__time-Profile_1")
  assert.equal(info.host, "rolemodelsoftware.harvestapp.com")
  assert.equal(info.profile, "Profile 1")
  assert.equal(info.appPart, "rolemodelsoftware.harvestapp.com__time")
})

test("chromeWebAppInfo ignores regular chromium windows", () => {
  assert.equal(M.chromeWebAppInfo("chromium"), null)
  assert.equal(M.chromeWebAppInfo("foot"), null)
  assert.equal(M.chromeWebAppInfo(""), null)
})

// -------------------------------------------------------------- prettyApp

test("prettyApp prefers the desktop name", () => {
  assert.equal(M.prettyApp("chromium", "chromium", "Chromium — Simbiotrek"), "Chromium — Simbiotrek")
})

test("prettyApp falls back to the webapp host, not Com time Profile 1", () => {
  assert.equal(
    M.prettyApp("chrome-rolemodelsoftware.harvestapp.com__time-Profile_1", "", ""),
    "rolemodelsoftware.harvestapp.com"
  )
})

test("prettyApp title-cases a simple class", () => {
  assert.equal(M.prettyApp("foot", "", ""), "Foot")
})

test("prettyApp uses the launcher name for a chrome web app", () => {
  assert.equal(
    M.prettyApp("chrome-launchpad.37signals.com__-Default", "", "Basecamp"),
    "Basecamp"
  )
})

test("prettyApp keeps the short mill label when a chrome app has no launcher", () => {
  assert.equal(M.prettyApp("chrome-launchpad.37signals.com__-Default", "", ""), "Launchpad")
  assert.equal(M.prettyApp("chrome-www.example.com__-Default", "", ""), "Example")
})

// -------------------------------------------------------------- findDesktopEntry

test("findDesktopEntry uses heuristicLookup id match for chromium", () => {
  const found = M.findDesktopEntry("chromium", "chromium", ENTRIES, byIdLookup)
  assert.equal(found.id, "chromium")
})

test("findDesktopEntry does not pick a Chromium profile by shared Icon=", () => {
  const found = M.findDesktopEntry("chromium", "chromium", ENTRIES, null)
  assert.equal(found.id, "chromium")
})

test("findDesktopEntry prefers id=chromium over profile launchers listed first", () => {
  const entries = [
    { id: "chromium-simbiotrek", name: "Chromium — Simbiotrek", icon: "chromium", startupClass: "chromium" },
    { id: "chromium", name: "Chromium", icon: "chromium", startupClass: "chromium" }
  ]
  assert.equal(M.findDesktopEntry("chromium", "", entries, null).id, "chromium")
})

test("findDesktopEntry ignores ambiguous StartupWMClass=chromium on profile launchers", () => {
  const entries = [
    { id: "chromium-simbiotrek", name: "Chromium — Simbiotrek", icon: "chromium", startupClass: "chromium" },
    { id: "chromium-rolemodel", name: "Chromium — RoleModel", icon: "chromium", startupClass: "chromium" }
  ]
  assert.equal(M.findDesktopEntry("chromium", "chromium", entries, null), null)
})

test("findDesktopEntry matches a webapp by StartupWMClass", () => {
  const found = M.findDesktopEntry(
    "chrome-rolemodelsoftware.harvestapp.com__time-Profile_1",
    "",
    ENTRIES,
    null
  )
  assert.equal(found.id, "Harvest")
})

test("findDesktopEntry matches a webapp by URL host when StartupWMClass is missing", () => {
  const entries = [
    { id: "Harvest", name: "Harvest", icon: "harvest", execString: "omarchy-launch-webapp https://rolemodelsoftware.harvestapp.com/time" }
  ]
  const found = M.findDesktopEntry(
    "chrome-rolemodelsoftware.harvestapp.com__time-Profile_1",
    "",
    entries,
    null
  )
  assert.equal(found.id, "Harvest")
})

test("findDesktopEntry prefers the matching Chromium profile for duplicate hosts", () => {
  const entries = [
    { id: "WhatsApp Personal", execString: 'omarchy-launch-webapp --profile-directory="Profile 2" https://web.whatsapp.com/' },
    { id: "WhatsApp Work", execString: 'omarchy-launch-webapp --profile-directory="Profile 1" https://web.whatsapp.com/' }
  ]
  const found = M.findDesktopEntry("chrome-web.whatsapp.com__-Profile_2", "", entries, null)
  assert.equal(found.id, "WhatsApp Personal")
})

test("execHasHost does not substring-match x.com inside box.com", () => {
  assert.equal(M.execHasHost("omarchy-launch-webapp https://box.com/", "x.com"), false)
  assert.equal(M.execHasHost("omarchy-launch-webapp https://x.com/", "x.com"), true)
})

test("profileFromExec reads --profile-directory", () => {
  assert.equal(M.profileFromExec('/usr/bin/chromium --profile-directory="Profile 2"'), "Profile 2")
  assert.equal(M.profileFromExec("omarchy-launch-webapp --profile-directory=Default https://x.test"), "Default")
})

// -------------------------------------------------------------- Ctrl+1–9 filtered rows

test("Ctrl+1 is the first filtered mill row, not an unfiltered neighbor", () => {
  const rows = [
    { prettyName: "Alpha", title: "notes", className: "alpha", appId: "alpha", profileName: "", workspaceId: 1, workspaceName: "1", scratchpad: false },
    { prettyName: "Beta", title: "notes", className: "beta", appId: "beta", profileName: "", workspaceId: 1, workspaceName: "1", scratchpad: false },
    { prettyName: "Gamma", title: "other", className: "gamma", appId: "gamma", profileName: "", workspaceId: 2, workspaceName: "2", scratchpad: false }
  ]
  const parts = M.partitionWindows(rows.filter((row) => M.matchesFilter(row, "notes")))
  assert.deepEqual(parts.mill.map((row) => row.prettyName), ["Alpha", "Beta"])
  assert.equal(M.pickFilteredIndex("mill", 0, parts.mill.length, parts.scratch.length), 0)
  assert.equal(parts.mill[M.pickFilteredIndex("mill", 0, parts.mill.length, parts.scratch.length)].prettyName, "Alpha")
  assert.equal(M.pickFilteredIndex("mill", 1, parts.mill.length, parts.scratch.length), 1)
  assert.equal(M.pickFilteredIndex("mill", 2, parts.mill.length, parts.scratch.length), -1)
  assert.equal(M.pickFilteredIndex("mill", 9, parts.mill.length, parts.scratch.length), -1)
})

test("Ctrl+1 targets the scratch dock only while that filtered section is current", () => {
  const rows = [
    { prettyName: "Mill", title: "notes", className: "m", appId: "m", profileName: "", workspaceId: 1, workspaceName: "1", scratchpad: false },
    { prettyName: "Scratch", title: "notes", className: "s", appId: "s", profileName: "", workspaceId: -99, workspaceName: "special:scratch", scratchpad: true }
  ]
  const parts = M.partitionWindows(rows.filter((row) => M.matchesFilter(row, "notes")))
  assert.equal(parts.mill[0].prettyName, "Mill")
  assert.equal(parts.scratch[0].prettyName, "Scratch")
  assert.equal(M.pickFilteredIndex("mill", 0, parts.mill.length, parts.scratch.length), 0)
  assert.equal(M.pickFilteredIndex("scratch", 0, parts.mill.length, parts.scratch.length), 0)
  const onlyScratch = M.partitionWindows(rows.filter((row) => row.scratchpad && M.matchesFilter(row, "notes")))
  assert.equal(M.pickFilteredIndex("mill", 0, onlyScratch.mill.length, onlyScratch.scratch.length), -1)
  assert.equal(M.pickFilteredIndex("scratch", 0, onlyScratch.mill.length, onlyScratch.scratch.length), 0)
})

if (process.exitCode) {
  console.error((passed) + " passed before failure")
} else {
  console.log(passed + " passed")
}
