// Neutrino - Quickshell
// ~/.config/quickshell/HyprTables.js
//
// Reads and rewrites plain `key = value` fields in hyprland.lua's table
// constructors, for the Settings window: the `input = { ... }` table inside
// hl.config (and its `touchpad` sub-table), and the table each hl.monitor()
// call takes. Plain functions over source text, like HyprBinds.js, whose
// tokenizer this uses so strings and comments can't fool it.
//
// Only a field whose value is one literal token (a number, a string, true or
// false) is rewritten in place. Anything computed is left alone and reported
// as not editable, rather than replaced with a literal that silently drops
// whatever the expression meant.

.import "HyprBinds.js" as HyprBinds

function code(src) {
    return HyprBinds.tokenize(src).filter(function(t) { return t.t !== "comment" })
}

var OPEN = { "{": 1, "(": 1, "[": 1 }
var CLOSE = { "}": 1, ")": 1, "]": 1 }

// index of the token closing the bracket at toks[i]
function matching(toks, i) {
    var depth = 0
    for (var j = i; j < toks.length; j++) {
        if (toks[j].t !== "op") continue
        if (OPEN[toks[j].v]) depth++
        else if (CLOSE[toks[j].v] && --depth === 0) return j
    }
    return -1
}

// Entries of the table whose "{" is toks[open]:
// [{ key, first, last, s, e, sep }] -- first/last are the value's token
// indexes, s/e its source span, sep the index of a trailing , or ; (or -1).
// Positional entries get key null.
function entries(toks, open) {
    var close = matching(toks, open)
    var out = []
    var i = open + 1
    while (i < close) {
        var j = i, depth = 0
        while (j < close) {
            var t = toks[j]
            if (t.t === "op") {
                if (OPEN[t.v]) depth++
                else if (CLOSE[t.v]) depth--
                else if (depth === 0 && (t.v === "," || t.v === ";")) break
            }
            j++
        }
        var named = toks[i].t === "name" && toks[i + 1] && toks[i + 1].v === "=" && i + 2 < j
        var first = named ? i + 2 : i
        if (first < j)
            out.push({ key: named ? toks[i].v : null, first: first, last: j - 1,
                s: toks[first].s, e: toks[j - 1].e, sep: j < close ? j : -1, keyStart: toks[i].s })
        i = j + 1
    }
    return { close: close, list: out }
}

function literal(toks, entry) {
    if (entry.first !== entry.last) return { editable: false }
    var t = toks[entry.first]
    if (t.t === "num") return { editable: true, value: Number(t.v) }
    if (t.t === "str") return { editable: true, value: t.v }
    if (t.t === "name" && (t.v === "true" || t.v === "false")) return { editable: true, value: t.v === "true" }
    return { editable: false }
}

function toLua(v) {
    if (typeof v === "boolean") return v ? "true" : "false"
    if (typeof v === "number") return String(Math.round(v * 1000) / 1000)
    return HyprBinds.luaString(v)
}

// { key: { editable, value } } for the named entries of a table
function read(toks, open) {
    var out = {}
    entries(toks, open).list.forEach(function(en) {
        if (en.key !== null) out[en.key] = literal(toks, en)
    })
    return out
}

// Follow `path` from a table: ["touchpad"] is the touchpad = { } entry.
function descend(toks, open, path) {
    for (var p = 0; p < path.length; p++) {
        var en = entries(toks, open).list.find(function(x) { return x.key === path[p] })
        if (!en || toks[en.first].v !== "{" || matching(toks, en.first) !== en.last) return -1
        open = en.first
    }
    return open
}

// leading whitespace of the line holding position pos
function indentAt(src, pos) {
    var ls = src.lastIndexOf("\n", pos - 1) + 1
    return /^[ \t]*/.exec(src.slice(ls))[0]
}

// Set key = value in the table at toks[open]. Returns the new source, or
// null when the existing value isn't a literal.
function setIn(src, toks, open, key, value) {
    var ents = entries(toks, open)
    var en = ents.list.find(function(x) { return x.key === key })
    if (en) {
        if (!literal(toks, en).editable) return null
        return src.slice(0, en.s) + toLua(value) + src.slice(en.e)
    }
    var line = key + " = " + toLua(value) + ","
    var named = ents.list.filter(function(x) { return x.key !== null })
    // Line up with the table's last plain field and go straight after it:
    // after its separator, adding one if it had none. Sub-tables come after
    // plain fields in this config, so a new plain field goes above them.
    var anchor = named.filter(function(x) { return toks[x.first].v !== "{" }).pop() || named.pop()
    if (anchor) {
        var indent = indentAt(src, anchor.keyStart)
        if (anchor.sep >= 0) {
            var at = toks[anchor.sep].e
            return src.slice(0, at) + "\n" + indent + line + src.slice(at)
        }
        return src.slice(0, anchor.e) + ",\n" + indent + line + src.slice(anchor.e)
    }
    var brace = toks[ents.close]
    var inner = indentAt(src, toks[open].s) + "    "
    return src.slice(0, toks[open].e) + "\n" + inner + line + "\n"
        + indentAt(src, brace.s) + src.slice(brace.s)
}

// --- input ---------------------------------------------------------------

// The `input = { }` table: the first one passed inside an hl.config({ }).
function inputTable(toks) {
    for (var i = 0; i + 3 < toks.length; i++) {
        if (toks[i].v === "hl" && toks[i + 1].v === "." && toks[i + 2].v === "config"
                && toks[i + 3].v === "(" && toks[i + 4] && toks[i + 4].v === "{") {
            var open = descend(toks, i + 4, ["input"])
            if (open >= 0) return open
        }
    }
    return -1
}

// { found, fields: { key: {editable, value} }, touchpad: {...} }
function readInput(src) {
    var toks = code(src)
    var open = inputTable(toks)
    if (open < 0) return { found: false, fields: {}, touchpad: {} }
    var tp = descend(toks, open, ["touchpad"])
    return { found: true, fields: read(toks, open), touchpad: tp >= 0 ? read(toks, tp) : {} }
}

// sub: "" for input itself, "touchpad" for input.touchpad
function setInput(src, sub, key, value) {
    var toks = code(src)
    var open = inputTable(toks)
    if (open < 0) return null
    if (sub !== "") {
        var tp = descend(toks, open, [sub])
        if (tp < 0) {
            // no sub-table yet: add one, then set the field in it
            var withSub = setInRaw(src, toks, open, sub)
            return withSub === null ? null : setInput(withSub, sub, key, value)
        }
        open = tp
    }
    return setIn(src, toks, open, key, value)
}

function setInRaw(src, toks, open, key) {
    var ents = entries(toks, open)
    var last = ents.list[ents.list.length - 1]
    if (!last) return null
    var indent = indentAt(src, last.keyStart)
    var at = last.sep >= 0 ? toks[last.sep].e : last.e
    var comma = last.sep >= 0 ? "" : ","
    return src.slice(0, at) + comma + "\n\n" + indent + key + " = {\n" + indent + "},"
        + src.slice(at)
}

// --- monitors ------------------------------------------------------------

// token index of the "{" opening each hl.monitor({ ... }) call, in order
function monitorOpens(toks) {
    var out = []
    for (var i = 0; i + 4 < toks.length; i++) {
        if (toks[i].v === "hl" && toks[i + 1].v === "." && toks[i + 2].v === "monitor"
                && toks[i + 3].v === "(" && toks[i + 4].v === "{")
            out.push(i + 4)
    }
    return out
}

// [{ index, output, fields }] for each hl.monitor({ ... }) call, in order
function readMonitors(src) {
    var toks = code(src)
    return monitorOpens(toks).map(function(open, index) {
        var fields = read(toks, open)
        return { index: index, output: fields.output && fields.output.editable
            ? String(fields.output.value) : null, fields: fields }
    })
}

// The rule a connected output falls under: its own, else the catch-all ""
// rule. Hyprland takes the last matching rule, so search from the end.
function ruleFor(rules, name) {
    for (var i = rules.length - 1; i >= 0; i--) if (rules[i].output === name) return rules[i]
    for (i = rules.length - 1; i >= 0; i--) if (rules[i].output === "") return rules[i]
    return null
}

function setMonitor(src, index, key, value) {
    var toks = code(src)
    var open = monitorOpens(toks)[index]
    return open === undefined ? null : setIn(src, toks, open, key, value)
}

// A new rule for one output, after the last hl.monitor() call or at the end.
function addMonitor(src, fields) {
    var toks = code(src)
    var at = src.length
    for (var i = toks.length - 1; i >= 0; i--) {
        if (toks[i].v === "monitor" && toks[i - 1] && toks[i - 1].v === "." && toks[i + 1] && toks[i + 1].v === "(") {
            at = toks[matching(toks, i + 1)].e
            break
        }
    }
    var body = Object.keys(fields).map(function(k) {
        return "    " + k + " = " + toLua(fields[k]) + ","
    }).join("\n")
    return src.slice(0, at) + "\n\nhl.monitor({\n" + body + "\n})" + src.slice(at)
}
