export interface ArchiveFieldVersions {
  listId: number
  archived: number
  archivedAt: number
}

export interface ArchiveRepairContext {
  activeListIds: Set<string>
  archivedListTimes: Set<number>
}

/**
 * Detect the exact state produced by the old client apply order and return a
 * timestamp that wins over every corrupted field version.
 */
export function getMisappliedArchiveRepairTime(
  data: Record<string, unknown>,
  updatedAt: number,
  versions: ArchiveFieldVersions,
  context: ArchiveRepairContext,
  now: number = Date.now()
): number | null {
  const listId = data.listId
  const archivedAt = data.archivedAt
  if (
    data.deleted === true ||
    data.archived !== true ||
    typeof listId !== 'string' ||
    !context.activeListIds.has(listId) ||
    typeof archivedAt !== 'number' ||
    !Number.isSafeInteger(archivedAt) ||
    !context.archivedListTimes.has(archivedAt) ||
    versions.listId >= versions.archived ||
    versions.archivedAt !== versions.archived ||
    archivedAt !== versions.archived
  ) {
    return null
  }

  return Math.max(
    now + 1,
    updatedAt + 1,
    versions.listId + 1,
    versions.archived + 1,
    versions.archivedAt + 1
  )
}
