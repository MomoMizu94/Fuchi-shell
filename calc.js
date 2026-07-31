// Expression evaluator for the app launcher's calculator mode.
//
// Hand-rolled rather than eval() or a shell-out: QML's JS engine restricts
// eval, and the launcher's `results` property is a synchronous binding, so an
// async Process round-trip per keystroke would not fit. A closed grammar also
// means a mistyped app name can never execute anything.

const CONSTANTS = {
    pi: Math.PI,
    tau: Math.PI * 2,
    e: Math.E
}

const FUNCTIONS = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs,
    round: Math.round, floor: Math.floor, ceil: Math.ceil,
    ln: Math.log, log: Math.log10, log2: Math.log2, exp: Math.exp,
    sin: Math.sin, cos: Math.cos, tan: Math.tan,
    asin: Math.asin, acos: Math.acos, atan: Math.atan
}

// Cheap pre-filter for auto-detect in normal (non-">") search mode: a query
// only counts as a candidate expression if it has a digit AND an operator.
// This is what keeps "Firefox", "1password", "7-zip" and "python3 -m" out of
// calculator mode — those that slip past still fail to parse below.
function looksLikeMath(src) {
    return /\d/.test(src) && /[-+*/^%()]/.test(src)
}

// Returns an array of {t, v} tokens, or null if the source contains anything
// outside the grammar. `t` is "num", "name", or the operator character itself.
function tokenize(src) {
    const s = src.replace(/\*\*/g, "^")
    const tokens = []
    let i = 0
    while (i < s.length) {
        const c = s[i]
        if (/\s/.test(c)) { i++; continue }
        if (/[0-9.]/.test(c)) {
            const m = /^\d*\.?\d+/.exec(s.slice(i))
            if (!m) return null            // a bare "." or malformed number
            tokens.push({ t: "num", v: parseFloat(m[0]) })
            i += m[0].length
            continue
        }
        if (/[a-zA-Z]/.test(c)) {
            const m = /^[a-zA-Z]+[0-9]*/.exec(s.slice(i))
            tokens.push({ t: "name", v: m[0].toLowerCase() })
            i += m[0].length
            continue
        }
        if ("+-*/%^()".indexOf(c) !== -1) {
            tokens.push({ t: c })
            i++
            continue
        }
        return null                        // unrecognised character
    }
    return tokens
}

// Recursive descent over the token array. Each parse* function reads from
// `st.tokens` at `st.i` and throws on a malformed expression; evaluate()
// catches. Grammar:
//   expr  := term (('+'|'-') term)*
//   term  := unary (('*'|'/'|'%') unary)*
//   unary := ('-'|'+') unary | power
//   power := atom ('^' unary)?      -- right-assoc, so 2^3^2 == 512
//   atom  := number | constant | func '(' expr ')' | '(' expr ')'
// Implicit multiplication ("2pi", "2(3+4)") is deliberately unsupported.
function peek(st) {
    return st.i < st.tokens.length ? st.tokens[st.i] : null
}

function parseExpr(st) {
    let left = parseTerm(st)
    for (let tok = peek(st); tok && (tok.t === "+" || tok.t === "-"); tok = peek(st)) {
        st.i++
        const right = parseTerm(st)
        left = tok.t === "+" ? left + right : left - right
    }
    return left
}

function parseTerm(st) {
    let left = parseUnary(st)
    for (let tok = peek(st); tok && (tok.t === "*" || tok.t === "/" || tok.t === "%"); tok = peek(st)) {
        st.i++
        const right = parseUnary(st)
        left = tok.t === "*" ? left * right : tok.t === "/" ? left / right : left % right
    }
    return left
}

function parseUnary(st) {
    const tok = peek(st)
    if (tok && (tok.t === "-" || tok.t === "+")) {
        st.i++
        const value = parseUnary(st)
        return tok.t === "-" ? -value : value
    }
    return parsePower(st)
}

function parsePower(st) {
    const base = parseAtom(st)
    const tok = peek(st)
    if (tok && tok.t === "^") {
        st.i++
        return Math.pow(base, parseUnary(st))
    }
    return base
}

function parseAtom(st) {
    const tok = peek(st)
    if (!tok) throw "unexpected end"
    if (tok.t === "num") { st.i++; return tok.v }
    if (tok.t === "(") {
        st.i++
        const value = parseExpr(st)
        const close = peek(st)
        if (!close || close.t !== ")") throw "expected )"
        st.i++
        return value
    }
    if (tok.t === "name") {
        st.i++
        if (tok.v in CONSTANTS) return CONSTANTS[tok.v]
        if (tok.v in FUNCTIONS) {
            const open = peek(st)
            if (!open || open.t !== "(") throw "expected ( after " + tok.v
            st.i++
            const arg = parseExpr(st)
            const close = peek(st)
            if (!close || close.t !== ")") throw "expected )"
            st.i++
            return FUNCTIONS[tok.v](arg)
        }
        throw "unknown name " + tok.v
    }
    throw "unexpected token"
}

// { ok: true, value } on success, { ok: false } otherwise. Non-finite results
// (1/0, sqrt(-1)) count as failures so the UI shows the error state instead of
// "Infinity"/"NaN".
function evaluate(src) {
    if (!src || src.trim() === "") return { ok: false }
    const tokens = tokenize(src)
    if (!tokens || tokens.length === 0) return { ok: false }
    const st = { tokens: tokens, i: 0 }
    let value
    try {
        value = parseExpr(st)
    } catch (e) {
        return { ok: false }
    }
    if (st.i !== tokens.length) return { ok: false }   // trailing junk
    if (typeof value !== "number" || !isFinite(value)) return { ok: false }
    return { ok: true, value: value }
}

// Machine-readable number string — no thousands separators, since this is
// exactly what gets copied to the clipboard.
function format(n) {
    if (n === 0) return "0"                 // also normalises -0
    const magnitude = Math.abs(n)
    // Extremes go exponential *before* any de-noising: rounding to a fixed
    // number of decimals would collapse 1e-13 to a bare "0".
    if (magnitude >= 1e15 || magnitude < 1e-9)
        return n.toExponential(6).replace("e+", "e")
    // Round-tripping through toPrecision is what turns 0.1+0.2 into "0.3"
    // rather than "0.30000000000000004". Unlike rounding to a fixed decimal
    // place it de-noises correctly at any magnitude.
    return String(parseFloat(n.toPrecision(12)))
}

// Result-row object for the launcher's ListView delegate, or null if `src`
// does not evaluate. Uses `glyph` (a Nerd Font codepoint) rather than `icon`
// (a themed icon name) deliberately: no icon theme is configured in this
// setup, so themed lookups outside hicolor resolve to "" and would render a
// blank icon column. U+F0A9A is from the same Material Design set as the
// search bar's own glyph. The delegate falls back to .comment for the
// subtitle because a plain object has no .genericName.
function entry(src) {
    const result = evaluate(src)
    if (!result.ok) return null
    return {
        kind: "calc",
        glyph: "󰪚",
        name: format(result.value),
        comment: src.trim() + "  ·  Enter to copy"
    }
}
