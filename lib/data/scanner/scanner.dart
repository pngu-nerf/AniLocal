/// Folder scanning + filename identification.
///
/// Seam #4: identification lives behind one interface so the filename parser is
/// swappable without touching anything else. Walk folders → parse title+episode
/// → produce candidate AniList matches. (Implemented in roadmap Stage 3.)
library;
