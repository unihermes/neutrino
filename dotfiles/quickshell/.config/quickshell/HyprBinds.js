// Neutrino - Quickshell
// ~/.config/quickshell/HyprBinds.js
//
// Reads and rewrites the hl.bind() calls in Hyprland's Lua config, for the
// Keybinds window. Plain functions over the source text, no QML, so the
// parsing can be exercised outside the shell.
//
// This is not a Lua interpreter. It tokenizes (so strings and comments can't
// fool it), tracks block nesting, resolves top-level `local x = "literal"`
// strings, and expands numeric for-loops so loop-generated binds still show
// up. Only a bind in its simplest shape is offered for editing:
//
//   hl.bind("KEYS" | ident .. " + KEYS", hl.dsp.exec_cmd("cmd" | ident) [, { opts }])
//
// on lines of its own, outside any block. Everything else is listed read-only
// with the reason, because rewriting an expression it only half understands
// is how a config gets broken.
//
// Categories come from marker comments, `-- --- Window Management ---`; a
// section banner (`---- WINDOW RULES ----`) ends the current one.

var MARKER = /^--\s*---\s+(.+?)\s+---\s*$/
var BANNER = /^----\s+.+?\s+----\s*$/

var MOD_ALIASES = {
    SUPER: "SUPER", WIN: "SUPER", LOGO: "SUPER", MOD4: "SUPER", META: "SUPER",
    CTRL: "CTRL", CONTROL: "CTRL",
    ALT: "ALT", MOD1: "ALT",
    SHIFT: "SHIFT",
    MOD2: "MOD2", MOD3: "MOD3", MOD5: "MOD5", ALTGR: "MOD5",
}
var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT", "MOD2", "MOD3", "MOD5"]

// --- tokenizer -----------------------------------------------------------

// level of a long bracket opening at p ("[[" is 0, "[==[" is 2), or -1
function longBracket(src, p) {
    if (src[p] !== "[") return -1
    var q = p + 1
    while (src[q] === "=") q++
    return src[q] === "[" ? q - p - 1 : -1
}

function countNewlines(src, from, to) {
    var n = 0
    for (var i = from; i < to; i++) if (src[i] === "\n") n++
    return n
}

var ESCAPES = { n: "\n", t: "\t", r: "\r", "\\": "\\", "\"": "\"", "'": "'", "\n": "\n" }

// [{ t: "comment"|"str"|"name"|"num"|"op", v, s, e, line }], where v for a
// string is its decoded value
function tokenize(src) {
    var toks = []
    var i = 0, line = 1, n = src.length
    while (i < n) {
        var c = src[i]
        if (c === "\n") { line++; i++; continue }
        if (c === " " || c === "\t" || c === "\r") { i++; continue }
        var s = i, startLine = line, lb, e

        if (c === "-" && src[i + 1] === "-") {
            lb = longBracket(src, i + 2)
            if (lb >= 0) {
                var close = "]" + "=".repeat(lb) + "]"
                e = src.indexOf(close, i + 4 + lb)
                e = e < 0 ? n : e + close.length
            } else {
                e = src.indexOf("\n", i)
                if (e < 0) e = n
            }
            line += countNewlines(src, i, e)
            toks.push({ t: "comment", v: src.slice(i, e).replace(/\r$/, ""), s: s, e: e, line: startLine })
            i = e
            continue
        }

        if (c === "\"" || c === "'") {
            var j = i + 1, out = ""
            while (j < n && src[j] !== c && src[j] !== "\n") {
                if (src[j] === "\\" && j + 1 < n) {
                    var x = src[j + 1]
                    if (x === "\n") line++
                    out += ESCAPES[x] !== undefined ? ESCAPES[x] : "\\" + x
                    j += 2
                } else {
                    out += src[j++]
                }
            }
            e = Math.min(n, j + 1)
            toks.push({ t: "str", v: out, s: s, e: e, line: startLine })
            i = e
            continue
        }

        lb = longBracket(src, i)
        if (lb >= 0) {
            var closeStr = "]" + "=".repeat(lb) + "]"
            var body = i + 2 + lb
            e = src.indexOf(closeStr, body)
            var end = e < 0 ? n : e
            e = e < 0 ? n : e + closeStr.length
            line += countNewlines(src, i, e)
            // a newline straight after the opening bracket isn't part of the string
            toks.push({ t: "str", v: src.slice(body, end).replace(/^\r?\n/, ""), s: s, e: e, line: startLine })
            i = e
            continue
        }

        if (/[A-Za-z_]/.test(c)) {
            e = i + 1
            while (e < n && /[A-Za-z0-9_]/.test(src[e])) e++
            toks.push({ t: "name", v: src.slice(i, e), s: s, e: e, line: startLine })
            i = e
            continue
        }

        if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(src[i + 1] || ""))) {
            e = i + 1
            while (e < n && (/[0-9A-Za-z_]/.test(src[e]) || (src[e] === "." && src[e + 1] !== "."))) e++
            toks.push({ t: "num", v: src.slice(i, e), s: s, e: e, line: startLine })
            i = e
            continue
        }

        var three = src.substr(i, 3), two = src.substr(i, 2)
        var op = three === "..." ? three
            : ["..", "==", "~=", "<=", ">=", "::", "//", "<<", ">>"].indexOf(two) >= 0 ? two
            : c
        toks.push({ t: "op", v: op, s: s, e: i + op.length, line: startLine })
        i += op.length
    }
    return toks
}

// --- evaluation ----------------------------------------------------------

// A concatenation of strings, numbers and resolvable names; null otherwise.
function evalConcat(toks, env, locals) {
    if (toks.length === 0 || toks.length % 2 === 0) return null
    var out = ""
    for (var i = 0; i < toks.length; i++) {
        var t = toks[i]
        if (i % 2 === 1) {
            if (t.t !== "op" || t.v !== "..") return null
            continue
        }
        if (t.t === "str") out += t.v
        else if (t.t === "num") out += t.v
        else if (t.t === "name" && env[t.v] !== undefined) out += String(env[t.v])
        else if (t.t === "name" && locals[t.v] !== undefined) out += locals[t.v]
        else return null
    }
    return out
}

// Source text of a token run, with loop variables replaced by this
// iteration's value -- but not table keys (`workspace = i` keeps its key).
function substituted(src, toks, env) {
    if (toks.length === 0) return ""
    var out = "", pos = toks[0].s
    for (var i = 0; i < toks.length; i++) {
        var t = toks[i]
        out += src.slice(pos, t.s)
        var prev = toks[i - 1], next = toks[i + 1]
        var isVar = t.t === "name" && env[t.v] !== undefined
            && !(prev && prev.t === "op" && prev.v === ".")
            && !(next && next.t === "op" && next.v === "=")
        out += isVar ? String(env[t.v]) : src.slice(t.s, t.e)
        pos = t.e
    }
    return out
}

function describeRaw(path, inner) {
    var p = path.replace(/^hl\.dsp\./, "")
    function kv(key) {
        var m = inner.match(new RegExp(key + "\\s*=\\s*\"?([\\w.-]+)\"?"))
        return m ? m[1] : null
    }
    switch (p) {
    case "window.close":      return "Close window"
    case "window.fullscreen": return kv("mode") === "maximized" ? "Maximize window" : "Fullscreen window"
    case "window.float":      return "Toggle floating"
    case "window.pseudo":     return "Toggle pseudotile"
    case "window.drag":       return "Drag window"
    case "window.resize":     return "Resize window"
    case "exit":              return "Exit Hyprland"
    case "window.move":
        if (kv("workspace")) return "Move window to workspace " + kv("workspace")
        break
    case "focus":
        if (kv("workspace")) return "Go to workspace " + kv("workspace")
        if (kv("direction")) return "Focus " + kv("direction")
        break
    case "layout":
        var m = inner.match(/"([^"]+)"/)
        if (m) return "Layout: " + m[1]
        break
    }
    var words = p.replace(/[._]/g, " ")
    return words.charAt(0).toUpperCase() + words.slice(1)
}

function describeExec(cmd, ident) {
    if (ident) return "Launch " + ident.replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
    var w = cmd.trim().split(/\s+/)
    var first = (w[0] || "").replace(/^.*\//, "")
    if (w[1] && /^[a-z][a-z-]*$/.test(w[1])) first += " " + w[1]
    return "Run " + first
}

// --- keys ----------------------------------------------------------------

// { mods: canonical names in MOD_ORDER, rest: the non-modifier parts as typed }
function splitKeys(keys) {
    var parts = String(keys).split("+").map(function(s) { return s.trim() }).filter(function(s) { return s !== "" })
    var mods = [], rest = []
    for (var i = 0; i < parts.length; i++) {
        var m = MOD_ALIASES[parts[i].toUpperCase()]
        if (m) { if (mods.indexOf(m) < 0) mods.push(m) }
        else rest.push(parts[i])
    }
    mods.sort(function(a, b) { return MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b) })
    return { mods: mods, rest: rest }
}

// For comparison only: canonical modifiers, then the key uppercased
// (Hyprland matches keysym names case-insensitively).
function normalizeKeys(keys) {
    var k = splitKeys(keys)
    return k.mods.concat(k.rest.length ? [k.rest[k.rest.length - 1].toUpperCase()] : []).join(" + ")
}

// For writing: modifiers canonical and first, the key as typed.
function tidyKeys(keys) {
    var k = splitKeys(keys)
    return { text: k.mods.concat(k.rest).join(" + "), keyCount: k.rest.length }
}

// --- parse ---------------------------------------------------------------

function parse(src) {
    var toks = tokenize(src)
    var code = []
    for (var k = 0; k < toks.length; k++) {
        toks[k].k = k
        if (toks[k].t !== "comment") { toks[k].ci = code.length; code.push(toks[k]) }
    }
    function isOp(t, v) { return t && t.t === "op" && t.v === v }
    function isName(t, v) { return t && t.t === "name" && (v === undefined || t.v === v) }

    var lineStarts = [0]
    for (var p = 0; p < src.length; p++) if (src[p] === "\n") lineStarts.push(p + 1)

    var locals = {}
    var stack = []
    var expectDo = false
    var category = ""
    var categories = []
    var calls = []

    for (k = 0; k < toks.length; k++) {
        var tk = toks[k]
        if (tk.t === "comment") {
            var m = tk.v.match(MARKER)
            if (m) {
                category = m[1]
                if (!categories.some(function(c) { return c.name === category }))
                    categories.push({ name: category, insertLine: tk.line })
            } else if (BANNER.test(tk.v)) {
                category = ""
            }
            continue
        }
        if (tk.t !== "name") continue
        var ci = tk.ci
        if (isOp(code[ci - 1], ".") || isOp(code[ci - 1], ":")) continue

        switch (tk.v) {
        case "function": case "if": case "repeat":
            stack.push({ kind: "block" })
            break
        case "while":
            stack.push({ kind: "block" })
            expectDo = true
            break
        case "for":
            var frame = { kind: "for" }
            var c = code
            if (isName(c[ci + 1]) && isOp(c[ci + 2], "=") && c[ci + 3] && c[ci + 3].t === "num"
                    && isOp(c[ci + 4], ",") && c[ci + 5] && c[ci + 5].t === "num") {
                var step = 1, doAt = ci + 6
                if (isOp(c[ci + 6], ",") && c[ci + 7] && c[ci + 7].t === "num") { step = Number(c[ci + 7].v); doAt = ci + 8 }
                if (isName(c[doAt], "do") && step !== 0) {
                    frame.var = c[ci + 1].v
                    frame.from = Number(c[ci + 3].v)
                    frame.to = Number(c[ci + 5].v)
                    frame.step = step
                }
            }
            stack.push(frame)
            expectDo = true
            break
        case "do":
            if (expectDo) expectDo = false
            else stack.push({ kind: "block" })
            break
        case "end": case "until":
            var popped = stack.pop()
            if (popped) popped.endLine = tk.line
            break
        case "local":
            if (stack.length === 0 && isName(code[ci + 1]) && isOp(code[ci + 2], "=")
                    && code[ci + 3] && code[ci + 3].t === "str" && !isOp(code[ci + 4], ".."))
                locals[code[ci + 1].v] = code[ci + 3].v
            break
        case "hl":
            if (!(isOp(code[ci + 1], ".") && isName(code[ci + 2], "bind") && isOp(code[ci + 3], "("))) break
            var depth = 0, args = [], cur = [], closeTok = null
            for (var j = ci + 4; j < code.length; j++) {
                var t = code[j]
                if (t.t === "op" && (t.v === "(" || t.v === "{" || t.v === "[")) depth++
                else if (t.t === "op" && (t.v === ")" || t.v === "}" || t.v === "]")) {
                    if (depth === 0) { closeTok = t; break }
                    depth--
                } else if (isOp(t, ",") && depth === 0) {
                    args.push(cur); cur = []
                    continue
                }
                cur.push(t)
            }
            if (!closeTok) break
            if (cur.length) args.push(cur)
            var after = toks[closeTok.k + 1]
            calls.push({
                args: args,
                s: tk.s, e: closeTok.e,
                line: tk.line, endLine: closeTok.line,
                comment: after && after.t === "comment" && after.line === closeTok.line ? after : null,
                category: category,
                frames: stack.slice(),
            })
            k = closeTok.k
            break
        }
    }

    // `mod` in `mod .. " + Q"`: the prefix new SUPER binds are written with
    var prefixCounts = {}

    var rows = []
    for (var n = 0; n < calls.length; n++) {
        var call = calls[n]
        var a = call.args
        if (a.length < 2) continue

        // own lines: nothing but whitespace before the call, and nothing but
        // whitespace or its comment after
        var ls = lineStarts[call.line - 1]
        var le = call.endLine < lineStarts.length ? lineStarts[call.endLine] - 1 : src.length
        var tailEnd = call.comment ? call.comment.s : le
        var ownLines = /^[ \t]*$/.test(src.slice(ls, call.s)) && /^[ \t\r]*$/.test(src.slice(call.e, tailEnd))

        var k0 = a[0]
        var keysForm = k0.length === 1 && k0[0].t === "str" ? "literal"
            : k0.length === 3 && isName(k0[0]) && locals[k0[0].v] !== undefined && isOp(k0[1], "..") && k0[2].t === "str" ? "prefixed"
            : "expr"
        if (keysForm === "prefixed") prefixCounts[k0[0].v] = (prefixCounts[k0[0].v] || 0) + 1

        var d = a[1]
        var isExec = d.length >= 7 && isName(d[0], "hl") && isOp(d[1], ".") && isName(d[2], "dsp")
            && isOp(d[3], ".") && isName(d[4], "exec_cmd") && isOp(d[5], "(") && isOp(d[d.length - 1], ")")
        var inner = isExec ? d.slice(6, d.length - 1) : []
        var cmdForm = !isExec ? "raw"
            : inner.length === 1 && inner[0].t === "str" ? "literal"
            : inner.length === 1 && isName(inner[0]) && locals[inner[0].v] !== undefined ? "ident"
            : "expr"

        var path = ""
        for (var q = 0; q < d.length && !isOp(d[q], "("); q++) path += d[q].v
        var parenAt = q

        var opts = a.length >= 3 ? src.slice(a[2][0].s, a[2][a[2].length - 1].e) : ""
        var flags = []
        var fm, flagRe = /([A-Za-z_]\w*)\s*=\s*true/g
        while ((fm = flagRe.exec(opts)) !== null) flags.push(fm[1])

        // one env per loop iteration; a loop it can't count gives one
        // unresolved row
        var loops = call.frames.filter(function(f) { return f.kind === "for" })
        var envs = [{}]
        if (loops.some(function(f) { return f.var === undefined })) {
            envs = [{}]
        } else {
            for (var li = 0; li < loops.length; li++) {
                var L = loops[li], next = []
                for (var ei = 0; ei < envs.length && next.length < 500; ei++) {
                    for (var v = L.from; L.step > 0 ? v <= L.to : v >= L.to; v += L.step) {
                        var env = Object.assign({}, envs[ei])
                        env[L.var] = v
                        next.push(env)
                        if (next.length >= 500) break
                    }
                }
                envs = next
            }
        }

        var reason = ""
        if (loops.length) reason = "Generated by a loop"
        else if (call.frames.length) reason = "Inside a block"
        else if (!isExec) reason = "Not a command bind"
        else if (keysForm === "expr") reason = "Keys are built from an expression"
        else if (cmdForm === "expr") reason = "Command is built from an expression"
        else if (!ownLines) reason = "Shares a line with other code"

        var outer = call.frames.length ? call.frames[0] : null

        for (var en = 0; en < envs.length; en++) {
            var envN = envs[en]
            var keys = evalConcat(k0, envN, locals)
            var keysText = keys !== null ? keys : substituted(src, k0, envN)
            var command, desc
            if (isExec) {
                var cv = evalConcat(inner, envN, locals)
                command = cv !== null ? cv : substituted(src, inner, envN)
                desc = describeExec(command, cmdForm === "ident" ? inner[0].v : "")
            } else {
                command = substituted(src, d, envN).replace(/^hl\.dsp\./, "")
                desc = describeRaw(path, substituted(src, d.slice(parenAt), envN))
            }
            var commentText = call.comment ? call.comment.v.replace(/^--\s*/, "").trim() : ""
            rows.push({
                id: call.s + ":" + en,
                callStart: call.s,
                line: call.line,
                endLine: call.endLine,
                category: call.category,
                keys: keysText,
                norm: normalizeKeys(keysText),
                command: command,
                isExec: isExec,
                comment: commentText,
                desc: commentText !== "" ? commentText : desc,
                autoDesc: desc,
                flags: flags,
                editable: reason === "" && keys !== null,
                reason: reason,
                keysForm: keysForm,
                keysIdent: keysForm === "prefixed" ? k0[0].v : "",
                keysSpan: [k0[0].s, k0[k0.length - 1].e],
                keysSrc: src.slice(k0[0].s, k0[k0.length - 1].e),
                cmdSpan: [d[0].s, d[d.length - 1].e],
                cmdSrc: src.slice(d[0].s, d[d.length - 1].e),
                optsSrc: opts,
                callEnd: call.e,
                commentSpan: call.comment ? [call.comment.s, call.comment.e] : null,
                insertLine: outer && outer.endLine ? outer.endLine : call.endLine,
            })
        }
    }

    // a category's new binds go after its last one
    for (var r = 0; r < rows.length; r++) {
        for (var cc = 0; cc < categories.length; cc++)
            if (categories[cc].name === rows[r].category)
                categories[cc].insertLine = Math.max(categories[cc].insertLine, rows[r].insertLine)
    }

    // duplicates already in the file get flagged too
    var byNorm = {}
    rows.forEach(function(row) { (byNorm[row.norm] = byNorm[row.norm] || []).push(row) })
    rows.forEach(function(row) {
        row.conflict = byNorm[row.norm].some(function(o) { return o.callStart !== row.callStart })
    })

    var prefixIdent = ""
    for (var id in prefixCounts)
        if (prefixIdent === "" || prefixCounts[id] > prefixCounts[prefixIdent]) prefixIdent = id

    return {
        src: src,
        rows: rows,
        categories: categories,
        locals: locals,
        prefixIdent: prefixIdent,
        lineStarts: lineStarts,
    }
}

// Other binds on the same combo, leaving out the call being edited.
function conflictsFor(model, keys, exceptCallStart) {
    var norm = normalizeKeys(keys)
    if (norm === "") return []
    return model.rows.filter(function(r) { return r.norm === norm && r.callStart !== exceptCallStart })
}

// --- rewrite -------------------------------------------------------------

function luaString(s) {
    return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
        .replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t") + "\""
}

function oneLine(s) {
    return String(s || "").replace(/\s*[\r\n]+\s*/g, " ").trim()
}

// keeps the file's `mod .. " + Q"` style when the combo starts with mod's value
function keysSource(keys, ident, locals) {
    if (ident && locals[ident] !== undefined) {
        var p = locals[ident] + " + "
        if (keys.indexOf(p) === 0 && keys.length > p.length)
            return ident + " .. " + luaString(" + " + keys.slice(p.length))
    }
    return luaString(keys)
}

function lineRange(model, first, last) {
    var s = model.lineStarts[first - 1]
    var e = last < model.lineStarts.length ? model.lineStarts[last] : model.src.length
    return [s, e]
}

function callSource(keysSrc, cmdSrc, optsSrc) {
    return "hl.bind(" + [keysSrc, cmdSrc].concat(optsSrc ? [optsSrc] : []).join(", ") + ")"
}

function insertCall(model, category, text) {
    var cat = null
    for (var i = 0; i < model.categories.length; i++)
        if (model.categories[i].name === category) cat = model.categories[i]
    var line = cat ? cat.insertLine
        : model.rows.length ? model.rows[model.rows.length - 1].insertLine
        : model.lineStarts.length
    var r = lineRange(model, line, line)
    var src = model.src
    var at = r[1]
    var indent = (src.slice(r[0], r[1]).match(/^[ \t]*/) || [""])[0]
    if (at === src.length && src.length > 0 && src[src.length - 1] !== "\n") { src += "\n"; at++ }
    return src.slice(0, at) + indent + text + "\n" + src.slice(at)
}

// fields: { keys, command, desc, category }
function addBind(model, fields) {
    var keys = tidyKeys(fields.keys).text
    var desc = oneLine(fields.desc)
    var text = callSource(keysSource(keys, model.prefixIdent, model.locals),
        "hl.dsp.exec_cmd(" + luaString(fields.command) + ")", "")
    return insertCall(model, fields.category, text + (desc ? " -- " + desc : ""))
}

function removeBind(model, row) {
    var r = lineRange(model, row.line, row.endLine)
    return model.src.slice(0, r[0]) + model.src.slice(r[1])
}

function editBind(model, row, fields) {
    var keys = tidyKeys(fields.keys).text
    var desc = oneLine(fields.desc)
    var keysChanged = keys !== row.keys
    var cmdChanged = fields.command !== row.command
    var newKeys = keysChanged ? keysSource(keys, row.keysIdent || model.prefixIdent, model.locals) : row.keysSrc
    var newCmd = cmdChanged ? "hl.dsp.exec_cmd(" + luaString(fields.command) + ")" : row.cmdSrc

    if (fields.category !== row.category) {
        var moved = parse(removeBind(model, row))
        return insertCall(moved, fields.category,
            callSource(newKeys, newCmd, row.optsSrc) + (desc ? " -- " + desc : ""))
    }

    // in place, span by span, so the file's column alignment survives
    var reps = []
    if (keysChanged) reps.push([row.keysSpan[0], row.keysSpan[1], newKeys])
    if (cmdChanged) reps.push([row.cmdSpan[0], row.cmdSpan[1], newCmd])
    if (desc !== row.comment) {
        if (row.commentSpan && desc === "") reps.push([row.callEnd, row.commentSpan[1], ""])
        else if (row.commentSpan) reps.push([row.commentSpan[0], row.commentSpan[1], "-- " + desc])
        else reps.push([row.callEnd, row.callEnd, " -- " + desc])
    }
    reps.sort(function(x, y) { return y[0] - x[0] })
    var src = model.src
    for (var i = 0; i < reps.length; i++)
        src = src.slice(0, reps[i][0]) + reps[i][2] + src.slice(reps[i][1])
    return src
}
