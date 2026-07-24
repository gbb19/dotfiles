# Git command performance review

The shared Git services currently use synchronous commands in three bounded,
user-triggered paths:

- repository root and current branch lookup;
- local and remote branch discovery when a branch picker opens;
- merge/feature resolution after the explicit current-line Diffview action.

These calls were intentionally left synchronous in this refactor. Branch picker
finders currently return a complete ordered list, while feature resolution is a
sequence of dependent Git queries. Converting either path to callbacks would
change cancellation, ordering, and error-reporting semantics.

If profiling shows visible blocking in a large repository, convert the service
boundary to `vim.system(..., callback)` and add cancellation when its picker
closes. Keep parsing functions synchronous and pure. Repository root/current
branch results are better candidates for short-lived caching with invalidation
on `DirChanged` and Git branch changes.
