import 'filename_parser.dart';

/// A focused, Anitomy-style heuristic parser for fansub/release filenames.
///
/// No maintained Dart Anitomy port exists, so this is a small purpose-built
/// tokenizer covering the common patterns: leading `[Group]` tags, bracketed
/// metadata, `_`/`.` separators, `S01E02` / `- 01` / `E01` episode markers, and
/// resolution/codec/source noise. It is deliberately imperfect — AniList search
/// is forgiving, and residual mistakes are corrected manually in Stage 5.
class HeuristicFilenameParser implements FilenameParser {
  const HeuristicFilenameParser();

  // Whole-token noise: encoding/source/audio metadata that is never title text.
  static const Set<String> _noiseWords = {
    'x264',
    'x265',
    'h264',
    'h265',
    'hevc',
    'avc',
    'xvid',
    'divx',
    'av1',
    'vp9',
    'aac',
    'ac3',
    'eac3',
    'flac',
    'opus',
    'dts',
    'mp3',
    'truehd',
    'pcm',
    'bd',
    'bdrip',
    'brrip',
    'bluray',
    'blu-ray',
    'web',
    'webrip',
    'web-dl',
    'webdl',
    'dvd',
    'dvdrip',
    'hdtv',
    'tvrip',
    'remux',
    'raw',
    'repack',
    '8bit',
    '10bit',
    '10bits',
    'hi10',
    'hi10p',
    'multi',
    'dual',
    'dualaudio',
    'subs',
    'sub',
    'subbed',
    'dubbed',
    'uncensored',
    'uncen',
    'censored',
    'eng',
    'jpn',
    'esp',
    'multisubs',
  };

  // Bare leading source/site-ripper prefixes (no brackets), e.g. AnimePahe.
  // Deliberately TINY and non-exhaustive — the general safety net is the
  // identifier's retry-without-leading-word. Do not grow this into a site
  // denylist treadmill.
  static const Set<String> _sourcePrefixes = {'animepahe'};

  // Numeric tokens that are resolutions/years, never episode numbers.
  static const Set<int> _resolutionNumbers = {
    360,
    480,
    540,
    576,
    720,
    1080,
    1440,
    2160,
  };

  static final RegExp _ext = RegExp(r'\.[A-Za-z0-9]{1,5}$');
  static final RegExp _leadingGroup = RegExp(r'^\[([^\]]+)\]');
  static final RegExp _seasonEpisode = RegExp(
    r'^S(\d{1,2})E(\d{1,3})$',
    caseSensitive: false,
  );
  static final RegExp _seasonOnly = RegExp(
    r'^S(\d{1,2})$',
    caseSensitive: false,
  );
  static final RegExp _episodeToken = RegExp(
    r'^(?:E|EP|EPISODE)(\d{1,4})$',
    caseSensitive: false,
  );
  static final RegExp _numberWithVersion = RegExp(r'^(\d{1,4})(?:v\d+)?$');
  static final RegExp _resOrDims = RegExp(
    r'^(\d{3,4}p|\d{3,4}x\d{3,4})$',
    caseSensitive: false,
  );
  static final RegExp _crc = RegExp(r'^[0-9a-fA-F]{8}$');
  static final RegExp _version = RegExp(r'^v\d+$', caseSensitive: false);

  @override
  ParsedFilename parse(String filename) {
    var name = filename.replaceFirst(_ext, '');

    String? group;
    final gm = _leadingGroup.firstMatch(name);
    if (gm != null) {
      group = gm.group(1)!.trim();
      name = name.substring(gm.end);
    }

    // Drop remaining bracketed metadata and orphan brackets.
    name = name
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[\[\]()]'), ' ');

    // Separators -> spaces (keep a lone '-' as an episode delimiter token).
    name = name.replaceAll(RegExp(r'[._]'), ' ');

    final tokens = name
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    int? season;
    int? episode;
    int titleEnd = tokens.length;

    // (a) S01E02
    for (var i = 0; i < tokens.length; i++) {
      final m = _seasonEpisode.firstMatch(tokens[i]);
      if (m != null) {
        season = int.parse(m.group(1)!);
        episode = int.parse(m.group(2)!);
        titleEnd = i;
        break;
      }
    }

    // (b) lone '-' followed by an episode number (the strongest fansub signal;
    //     keeps numbers inside titles like "Mob Psycho 100" intact).
    if (episode == null) {
      for (var i = 0; i < tokens.length - 1; i++) {
        if (tokens[i] != '-') continue;
        final m = _numberWithVersion.firstMatch(tokens[i + 1]);
        if (m != null && !_isResolutionOrYear(tokens[i + 1])) {
          episode = int.parse(m.group(1)!);
          titleEnd = i;
          break;
        }
      }
    }

    // (c) E01 / EP01 / Episode 01
    if (episode == null) {
      for (var i = 0; i < tokens.length; i++) {
        final m = _episodeToken.firstMatch(tokens[i]);
        if (m != null) {
          episode = int.parse(m.group(1)!);
          titleEnd = i;
          break;
        }
        final lower = tokens[i].toLowerCase();
        if ((lower == 'e' || lower == 'ep' || lower == 'episode') &&
            i + 1 < tokens.length &&
            RegExp(r'^\d{1,4}$').hasMatch(tokens[i + 1])) {
          episode = int.parse(tokens[i + 1]);
          titleEnd = i;
          break;
        }
      }
    }

    // (d) trailing bare number, skipping trailing noise (e.g. "Title 01 1080p").
    if (episode == null) {
      for (var i = tokens.length - 1; i > 0; i--) {
        final tok = tokens[i];
        final m = _numberWithVersion.firstMatch(tok);
        if (m != null && !_isResolutionOrYear(tok)) {
          episode = int.parse(m.group(1)!);
          titleEnd = i;
          break;
        }
        if (_isNoise(tok)) continue;
        break; // a real (title) word at the tail -> no trailing episode
      }
    }

    // Standalone season marker (e.g. "Title S2 - 01").
    for (var i = 0; i < titleEnd; i++) {
      final m = _seasonOnly.firstMatch(tokens[i]);
      if (m != null) {
        season ??= int.parse(m.group(1)!);
      }
    }

    final titleTokens = tokens
        .sublist(0, titleEnd)
        .where(
          (t) =>
              t != '-' &&
              !_isNoise(t) &&
              !_seasonOnly.hasMatch(t) &&
              !_version.hasMatch(t),
        )
        .toList();

    // Drop a known bare source prefix when it leads the title (keep at least
    // one token). General unknown prefixes are handled by the identifier's
    // retry instead.
    if (titleTokens.length > 1 &&
        _sourcePrefixes.contains(titleTokens.first.toLowerCase())) {
      titleTokens.removeAt(0);
    }

    final title = titleTokens
        .join(' ')
        .replaceAll(RegExp(r'^[\s\-_:]+|[\s\-_:]+$'), '')
        .trim();

    return ParsedFilename(
      rawName: filename,
      title: title,
      episodeNumber: episode,
      seasonNumber: season,
      releaseGroup: group,
    );
  }

  static bool _isResolutionOrYear(String token) {
    final base = _numberWithVersion.firstMatch(token)?.group(1) ?? token;
    final n = int.tryParse(base);
    if (n == null) return false;
    if (_resolutionNumbers.contains(n)) return true;
    return n >= 1900 && n <= 2099; // year
  }

  static bool _isNoise(String token) {
    final lower = token.toLowerCase();
    return _noiseWords.contains(lower) ||
        _resOrDims.hasMatch(token) ||
        _crc.hasMatch(token);
  }
}
