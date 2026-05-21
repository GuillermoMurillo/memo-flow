# memo-flow e2e target seed

This is the seed fixture for e2e tests. Its purpose is to represent a brand-new,
empty project that a memo-flow consumer would start from.

Each e2e test run copies these files into a fresh temp directory, initializes it
as a git repo, then creates a worktree of it as the actual test surface. The
worktree is torn down after assertions; the seed files here stay committed and
clean.

Do not add memo-flow state here. Keep this near-empty.
