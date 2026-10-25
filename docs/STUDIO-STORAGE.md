# Studio storage policy

Where Studio work lives, what is precious, and what may be cleaned up.
The portable defaults live in
`desktop/studio-storage/storage-policy.json`; Hornero/CLI owns any
operation on real filesystems, and the installer and Shell present the
same policy. Nothing in this policy repartitions, formats, or deletes
anything.

## Location classes

| Location | Default | Class | Backup/snapshots |
| --- | --- | --- | --- |
| Projects | `~/Studio/Projects` | User-owned work | Include |
| Assets | `~/Studio/Assets` | User-owned media | Include |
| Cache | `~/.cache/hornero/studio` | Regenerable | Exclude |
| Scratch | `~/Studio/Scratch` | Temporary renders | Exclude |

- **User-owned** (Projects, Assets): never auto-deleted, moved, or
  scanned. Always part of backups and snapshots.
- **Regenerable** (Cache): previews, thumbnails, and rebuildable
  intermediates. Cleanup candidates only when their owner is known,
  and always previewed first.
- **Temporary** (Scratch): render/export working space. Same cleanup
  rule as cache; a full scratch disk stops a render safely, it never
  corrupts or rewrites source media.

## Choices, not mandates

Accept the defaults, pick other locations (including an external
volume), or defer entirely. Changing a location never moves existing
files by itself: migration is a separate, previewed operation with a
rollback path, and config updates preserve your edits and prior paths.

Before a chosen location is used, the owning tool should validate
ownership, permissions, available capacity, and symlink/mount state —
including a volume that is not currently mounted. This config policy
defines the semantics; it does not perform those checks itself.

## Space pressure

- Warning threshold: below 10% free space, surfaces should warn with
  actionable guidance (largest cache/scratch candidates, previewed).
- Stop threshold: below 3% free space, a running render/export should
  stop safely before it can corrupt outputs or touch sources.
- Unknown files and project media are never cleanup candidates, no
  matter how large they are.

## Explicitly not in this policy

- No hard-coded partition layout or filesystem requirement.
- No automatic Btrfs NOCOW or any other integrity trade-off.
- No deletion to "make room" beyond the previewed cache/scratch rule.
