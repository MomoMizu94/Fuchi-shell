const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');
const logic = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../library.js'), 'utf8'), logic);
const books = [
    {name: 'Book 10', read: 10, meta: {tags: ['quiet'], languages: ['en'], artists: ['example']}},
    {name: 'Book 2', read: 20, meta: {tags: ['action'], languages: ['ja']}},
    {name: 'No metadata', read: 0, meta: {}},
];
test('combines title/artist search with include and exclude filters', () => {
    assert.equal(logic.filtered(books, 'example', {'tags:quiet': 1}, 'name').length, 1);
    assert.equal(logic.filtered(books, '', {'tags:quiet': -1}, 'name').length, 2);
    assert.equal(logic.filtered(books, '', {'languages:en': 1, 'tags:quiet': -1}, 'name').length, 0);
});
test('sorts numeric titles and recent reading without modifying the library', () => {
    assert.equal(logic.filtered(books, '', {}, 'name')[0].name, 'Book 2');
    assert.equal(logic.filtered(books, '', {}, 'recent')[0].read, 20);
    assert.equal(books[0].name, 'Book 10');
});
test('filters cycle through include, exclude and off without mutating old state', () => {
    const first = logic.toggle({}, 'tags:quiet');
    const second = logic.toggle(first, 'tags:quiet');
    const third = logic.toggle(second, 'tags:quiet');
    assert.equal(first['tags:quiet'], 1);
    assert.equal(second['tags:quiet'], -1);
    assert.equal(Object.keys(third).length, 0);
});
test('metadata values do not collide with object prototype property names', () => {
    const result = logic.facets([{meta: {tags: ['constructor', '__proto__']}}], 'tags', '');
    assert.equal(result.length, 2);
    assert.ok(result.every(facet => facet.count === 1));
});
