/// A show is "unavailable" iff it has source folders AND every one of them is
/// currently missing — a single connected source keeps a multi-source show
/// playable, so it stays un-greyed. The ONE rule the library grid, the show
/// page's banner and the play guards all apply, so they cannot disagree about
/// which shows are reachable. Pure; the sets come from the folder-health pass.
bool seriesUnavailable(Set<String> sourceFolders, Set<String> missingFolders) =>
    sourceFolders.isNotEmpty && sourceFolders.every(missingFolders.contains);
