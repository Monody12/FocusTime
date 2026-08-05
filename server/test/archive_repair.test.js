const test = require('node:test')
const assert = require('node:assert/strict')
const {
  getMisappliedArchiveRepairTime
} = require('../dist/sync/archive_repair')

const context = {
  activeListIds: new Set(['new-list']),
  archivedListTimes: new Set([200])
}

test('repairs a task moved before its previous list was archived', () => {
  const repairedAt = getMisappliedArchiveRepairTime(
    {
      listId: 'new-list',
      archived: true,
      archivedAt: 200,
      deleted: false
    },
    300,
    { listId: 100, archived: 200, archivedAt: 200 },
    context,
    400
  )

  assert.equal(repairedAt, 401)
})

test('does not unarchive a deliberately archived task', () => {
  const repairedAt = getMisappliedArchiveRepairTime(
    {
      listId: 'new-list',
      archived: true,
      archivedAt: 200,
      deleted: false
    },
    300,
    { listId: 100, archived: 210, archivedAt: 210 },
    context,
    400
  )

  assert.equal(repairedAt, null)
})

test('does not unarchive a task moved after the archive event', () => {
  const repairedAt = getMisappliedArchiveRepairTime(
    {
      listId: 'new-list',
      archived: true,
      archivedAt: 200,
      deleted: false
    },
    300,
    { listId: 250, archived: 200, archivedAt: 200 },
    context,
    400
  )

  assert.equal(repairedAt, null)
})
