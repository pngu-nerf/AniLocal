/// Local cache: Drift (SQLite) + cached art files on disk.
///
/// Seam #2: this is the PRIMARY read path. Repositories read from here; the UI
/// never waits on the network. Cache is a projection keyed by AniList ID — only
/// fields the UI renders. (Implemented in roadmap Stage 4.)
library;
