/// Every Settings category id, named ONCE.
///
/// A deep-link (`initialCategory`) and the category it opens must spell the id
/// identically, and one file is how they stay that way. The ids are session
/// memory only (the window remembers the last one for this app run), so
/// renaming one migrates nothing. Only [unmatchedCategoryId] is deep-linked
/// today — the header's Unmatched tab.
///
/// The seven tabs, each the answer to one question: Folders (what you own),
/// Sources (where information comes from), Playback (what the player does on
/// its own), Display (what the screens show), Unmatched (the worklist),
/// Maintenance (upkeep), About.
const String foldersCategoryId = 'folders';
const String sourcesCategoryId = 'sources';
const String playbackCategoryId = 'playback';
const String displayCategoryId = 'display';
const String unmatchedCategoryId = 'unmatched';
const String maintenanceCategoryId = 'maintenance';
const String aboutCategoryId = 'about';
