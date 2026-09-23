const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "../home-manager/modules/quickshell/desktop/Overlay.qml"), "utf8")
const model = source.match(/model: (shell\.overlayMode === "launcher"[\s\S]*?)\n\s*currentIndex:/)?.[1]
const filter = source.match(/property var filteredClipboardEntries: (.+)/)?.[1]
const activate = source.match(/function activateSelected\(\) \{([\s\S]*?)\n    \}/)?.[1]
const count = source.match(/const count = (shell\.overlayMode === "launcher".+)/)?.[1]
assert.ok(model && activate && count, "clipboard model, navigation, and activation must be present")

const entries = [
    { id: "1", text: "Alpha", mime: "" },
    { id: "2", text: "Needle", mime: "" },
    { id: "3", text: "other needle", mime: "" },
]

function createContext(query, selectedIndex = 0) {
    const copies = []
    const search = { text: query }
    const shell = { overlayMode: "clipboard" }
    const overlay = { clipboardEntries: entries, applications: [], selectedIndex }
    const context = { shell, overlay, search, selectedIndex, clipboardEntries: entries, applications: [],
        notifications: { trackedNotifications: [] },
        Quickshell: { execDetached: args => copies.push(args) } }
    if (filter) {
        Object.defineProperty(overlay, "filteredClipboardEntries", {
            get: () => vm.runInNewContext(filter, context),
        })
        Object.defineProperty(context, "filteredClipboardEntries", {
            get: () => overlay.filteredClipboardEntries,
        })
    }
    return { context, copies }
}

for (const [query, expected] of [
    ["", ["1", "2", "3"]],
    ["NEEDLE", ["2", "3"]],
    ["other", ["3"]],
    ["missing", []],
]) {
    const { context } = createContext(query)
    const actual = vm.runInNewContext(model, context)
    assert.deepEqual(Array.from(actual, entry => entry.id), expected, `search: ${query}`)
    assert.equal(vm.runInNewContext(count, context), expected.length, `navigation: ${query}`)
}

const { context, copies } = createContext("", 0)
context.search.text = "other"
assert.deepEqual(Array.from(vm.runInNewContext(model, context), entry => entry.id), ["3"])
vm.runInNewContext(`(function activateSelected() {${activate}\n})()`, context)
assert.equal(copies[0]?.[2], "3", "Enter should copy the filtered selection")

context.search.text = "missing"
vm.runInNewContext(`(function activateSelected() {${activate}\n})()`, context)
assert.equal(copies.length, 1, "Enter should not copy when nothing matches")
console.log("clipboard search and selection: OK")
