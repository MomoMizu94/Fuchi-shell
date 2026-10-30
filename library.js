// Pure view logic shared by the Library window and its tests.
function matches(book, query, filters) {
    const text = (book.name + " " + (book.meta.artists || []).join(" ")).toLowerCase()
    if (query.trim() && !text.includes(query.trim().toLowerCase())) return false
    for (const key of Object.keys(filters)) {
        const separator = key.indexOf(":")
        const field = key.slice(0, separator)
        const value = key.slice(separator + 1)
        const present = (book.meta[field] || []).includes(value)
        if ((filters[key] === 1) !== present) return false
    }
    return true
}

function filtered(books, query, filters, sort) {
    const result = books.filter(book => matches(book, query, filters))
    result.sort((a, b) => (sort === "recent" ? b.read - a.read : 0)
        || a.name.localeCompare(b.name, undefined, {numeric: true, sensitivity: "base"}))
    return result
}

function facets(books, field, query) {
    const counts = Object.create(null)
    for (const book of books)
        for (const value of book.meta[field] || []) counts[value] = (counts[value] || 0) + 1
    return Object.keys(counts).filter(value => value.includes(query.trim().toLowerCase()))
        .sort((a, b) => counts[b] - counts[a] || a.localeCompare(b))
        .map(value => ({value, count: counts[value]}))
}

function toggle(filters, key) {
    const next = Object.assign({}, filters)
    if (!next[key]) next[key] = 1
    else if (next[key] === 1) next[key] = -1
    else delete next[key]
    return next
}

