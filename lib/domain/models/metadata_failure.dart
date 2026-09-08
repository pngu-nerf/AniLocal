/// Why a metadata fetch failed — split by WHOSE end the fault is on, so the UI
/// can tell the user something actionable instead of a generic "can't reach".
///
/// The split is drawn on facts we can actually observe, never a guess:
///
/// * Did we get an HTTP response at all? No response means the request never
///   left our side of the wire — DNS, socket, TLS, timeout. That is
///   [connection], and it is the user's end.
/// * We got a response, so the user's connection demonstrably works. Now the
///   status and body say who refused: a 5xx, or a 4xx carrying AniList's own
///   GraphQL error body, is AniList answering for itself ([service]). A 4xx
///   with any other body (HTML, empty) was written by something in between —
///   an edge/WAF, corporate proxy, VPN or captive portal ([blocked]).
///
/// A domain model so the UI can branch on it without importing AniList types
/// (seam #1). AniSkip can reuse it if its failures ever need surfacing.
enum MetadataFailure {
  /// The request never reached AniList. Offline, DNS failure, TLS failure or
  /// timeout — the user's connection.
  connection,

  /// Something between the user and AniList refused the request before AniList
  /// saw it (proxy, VPN, network filter, captive portal, edge WAF).
  blocked,

  /// AniList itself answered with a failure — its API is down, disabled, or
  /// erroring. Nothing on the user's side will fix it.
  service,

  /// AniList answered 429: we asked too fast. Resolves on its own.
  rateLimited,
}
