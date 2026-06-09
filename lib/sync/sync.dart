/// The metadata pipeline: scanner → identifier → AniList fetch → write cache.
///
/// This is the FILL path only — it runs at scan/refresh, never on the UI read
/// path. Incremental: process new / moved / removed files, never refetch
/// unchanged items. (Implemented in roadmap Stages 3–4.)
library;
