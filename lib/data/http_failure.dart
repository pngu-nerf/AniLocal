import '../domain/models/metadata_failure.dart';

/// Attribute a bad HTTP status to one side of the wire.
///
/// Shared by every remote source so they all answer "whose fault is this?" the
/// same way — the rule was written for AniList and would otherwise be
/// re-derived, slightly differently, in each new client.
///
/// [carriesProviderError] means the body was the SERVICE'S OWN error envelope
/// (AniList's GraphQL `errors`, JSON:API's `errors`) — something only the
/// service itself writes.
MetadataFailure classifyHttpFailure(
  int status, {
  required bool carriesProviderError,
}) {
  if (status == 429) return MetadataFailure.rateLimited;
  // 5xx is server-side by definition, whoever rendered the page.
  if (status >= 500) return MetadataFailure.service;
  // A 4xx speaking the service's own error format is that service deliberately
  // refusing. A 4xx with any other body was written by something in between —
  // an edge/WAF, proxy, VPN or captive portal.
  return carriesProviderError
      ? MetadataFailure.service
      : MetadataFailure.blocked;
}
