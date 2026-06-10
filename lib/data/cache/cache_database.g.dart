// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $SeriesCacheTable extends SeriesCache
    with TableInfo<$SeriesCacheTable, CachedSeriesRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _anilistIdMeta = const VerificationMeta(
    'anilistId',
  );
  @override
  late final GeneratedColumn<int> anilistId = GeneratedColumn<int>(
    'anilist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _romajiMeta = const VerificationMeta('romaji');
  @override
  late final GeneratedColumn<String> romaji = GeneratedColumn<String>(
    'romaji',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _englishMeta = const VerificationMeta(
    'english',
  );
  @override
  late final GeneratedColumn<String> english = GeneratedColumn<String>(
    'english',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nativeTitleMeta = const VerificationMeta(
    'nativeTitle',
  );
  @override
  late final GeneratedColumn<String> nativeTitle = GeneratedColumn<String>(
    'native_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeCountMeta = const VerificationMeta(
    'episodeCount',
  );
  @override
  late final GeneratedColumn<int> episodeCount = GeneratedColumn<int>(
    'episode_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverImageUrlMeta = const VerificationMeta(
    'coverImageUrl',
  );
  @override
  late final GeneratedColumn<String> coverImageUrl = GeneratedColumn<String>(
    'cover_image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverImagePathMeta = const VerificationMeta(
    'coverImagePath',
  );
  @override
  late final GeneratedColumn<String> coverImagePath = GeneratedColumn<String>(
    'cover_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    anilistId,
    romaji,
    english,
    nativeTitle,
    format,
    episodeCount,
    coverImageUrl,
    coverImagePath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedSeriesRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('anilist_id')) {
      context.handle(
        _anilistIdMeta,
        anilistId.isAcceptableOrUnknown(data['anilist_id']!, _anilistIdMeta),
      );
    }
    if (data.containsKey('romaji')) {
      context.handle(
        _romajiMeta,
        romaji.isAcceptableOrUnknown(data['romaji']!, _romajiMeta),
      );
    }
    if (data.containsKey('english')) {
      context.handle(
        _englishMeta,
        english.isAcceptableOrUnknown(data['english']!, _englishMeta),
      );
    }
    if (data.containsKey('native_title')) {
      context.handle(
        _nativeTitleMeta,
        nativeTitle.isAcceptableOrUnknown(
          data['native_title']!,
          _nativeTitleMeta,
        ),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    if (data.containsKey('episode_count')) {
      context.handle(
        _episodeCountMeta,
        episodeCount.isAcceptableOrUnknown(
          data['episode_count']!,
          _episodeCountMeta,
        ),
      );
    }
    if (data.containsKey('cover_image_url')) {
      context.handle(
        _coverImageUrlMeta,
        coverImageUrl.isAcceptableOrUnknown(
          data['cover_image_url']!,
          _coverImageUrlMeta,
        ),
      );
    }
    if (data.containsKey('cover_image_path')) {
      context.handle(
        _coverImagePathMeta,
        coverImagePath.isAcceptableOrUnknown(
          data['cover_image_path']!,
          _coverImagePathMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {anilistId};
  @override
  CachedSeriesRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedSeriesRow(
      anilistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anilist_id'],
      )!,
      romaji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}romaji'],
      ),
      english: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}english'],
      ),
      nativeTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}native_title'],
      ),
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      ),
      episodeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_count'],
      ),
      coverImageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_image_url'],
      ),
      coverImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_image_path'],
      ),
    );
  }

  @override
  $SeriesCacheTable createAlias(String alias) {
    return $SeriesCacheTable(attachedDatabase, alias);
  }
}

class CachedSeriesRow extends DataClass implements Insertable<CachedSeriesRow> {
  final int anilistId;
  final String? romaji;
  final String? english;
  final String? nativeTitle;
  final String? format;
  final int? episodeCount;
  final String? coverImageUrl;
  final String? coverImagePath;
  const CachedSeriesRow({
    required this.anilistId,
    this.romaji,
    this.english,
    this.nativeTitle,
    this.format,
    this.episodeCount,
    this.coverImageUrl,
    this.coverImagePath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['anilist_id'] = Variable<int>(anilistId);
    if (!nullToAbsent || romaji != null) {
      map['romaji'] = Variable<String>(romaji);
    }
    if (!nullToAbsent || english != null) {
      map['english'] = Variable<String>(english);
    }
    if (!nullToAbsent || nativeTitle != null) {
      map['native_title'] = Variable<String>(nativeTitle);
    }
    if (!nullToAbsent || format != null) {
      map['format'] = Variable<String>(format);
    }
    if (!nullToAbsent || episodeCount != null) {
      map['episode_count'] = Variable<int>(episodeCount);
    }
    if (!nullToAbsent || coverImageUrl != null) {
      map['cover_image_url'] = Variable<String>(coverImageUrl);
    }
    if (!nullToAbsent || coverImagePath != null) {
      map['cover_image_path'] = Variable<String>(coverImagePath);
    }
    return map;
  }

  SeriesCacheCompanion toCompanion(bool nullToAbsent) {
    return SeriesCacheCompanion(
      anilistId: Value(anilistId),
      romaji: romaji == null && nullToAbsent
          ? const Value.absent()
          : Value(romaji),
      english: english == null && nullToAbsent
          ? const Value.absent()
          : Value(english),
      nativeTitle: nativeTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(nativeTitle),
      format: format == null && nullToAbsent
          ? const Value.absent()
          : Value(format),
      episodeCount: episodeCount == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeCount),
      coverImageUrl: coverImageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverImageUrl),
      coverImagePath: coverImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverImagePath),
    );
  }

  factory CachedSeriesRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedSeriesRow(
      anilistId: serializer.fromJson<int>(json['anilistId']),
      romaji: serializer.fromJson<String?>(json['romaji']),
      english: serializer.fromJson<String?>(json['english']),
      nativeTitle: serializer.fromJson<String?>(json['nativeTitle']),
      format: serializer.fromJson<String?>(json['format']),
      episodeCount: serializer.fromJson<int?>(json['episodeCount']),
      coverImageUrl: serializer.fromJson<String?>(json['coverImageUrl']),
      coverImagePath: serializer.fromJson<String?>(json['coverImagePath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'anilistId': serializer.toJson<int>(anilistId),
      'romaji': serializer.toJson<String?>(romaji),
      'english': serializer.toJson<String?>(english),
      'nativeTitle': serializer.toJson<String?>(nativeTitle),
      'format': serializer.toJson<String?>(format),
      'episodeCount': serializer.toJson<int?>(episodeCount),
      'coverImageUrl': serializer.toJson<String?>(coverImageUrl),
      'coverImagePath': serializer.toJson<String?>(coverImagePath),
    };
  }

  CachedSeriesRow copyWith({
    int? anilistId,
    Value<String?> romaji = const Value.absent(),
    Value<String?> english = const Value.absent(),
    Value<String?> nativeTitle = const Value.absent(),
    Value<String?> format = const Value.absent(),
    Value<int?> episodeCount = const Value.absent(),
    Value<String?> coverImageUrl = const Value.absent(),
    Value<String?> coverImagePath = const Value.absent(),
  }) => CachedSeriesRow(
    anilistId: anilistId ?? this.anilistId,
    romaji: romaji.present ? romaji.value : this.romaji,
    english: english.present ? english.value : this.english,
    nativeTitle: nativeTitle.present ? nativeTitle.value : this.nativeTitle,
    format: format.present ? format.value : this.format,
    episodeCount: episodeCount.present ? episodeCount.value : this.episodeCount,
    coverImageUrl: coverImageUrl.present
        ? coverImageUrl.value
        : this.coverImageUrl,
    coverImagePath: coverImagePath.present
        ? coverImagePath.value
        : this.coverImagePath,
  );
  CachedSeriesRow copyWithCompanion(SeriesCacheCompanion data) {
    return CachedSeriesRow(
      anilistId: data.anilistId.present ? data.anilistId.value : this.anilistId,
      romaji: data.romaji.present ? data.romaji.value : this.romaji,
      english: data.english.present ? data.english.value : this.english,
      nativeTitle: data.nativeTitle.present
          ? data.nativeTitle.value
          : this.nativeTitle,
      format: data.format.present ? data.format.value : this.format,
      episodeCount: data.episodeCount.present
          ? data.episodeCount.value
          : this.episodeCount,
      coverImageUrl: data.coverImageUrl.present
          ? data.coverImageUrl.value
          : this.coverImageUrl,
      coverImagePath: data.coverImagePath.present
          ? data.coverImagePath.value
          : this.coverImagePath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedSeriesRow(')
          ..write('anilistId: $anilistId, ')
          ..write('romaji: $romaji, ')
          ..write('english: $english, ')
          ..write('nativeTitle: $nativeTitle, ')
          ..write('format: $format, ')
          ..write('episodeCount: $episodeCount, ')
          ..write('coverImageUrl: $coverImageUrl, ')
          ..write('coverImagePath: $coverImagePath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    anilistId,
    romaji,
    english,
    nativeTitle,
    format,
    episodeCount,
    coverImageUrl,
    coverImagePath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedSeriesRow &&
          other.anilistId == this.anilistId &&
          other.romaji == this.romaji &&
          other.english == this.english &&
          other.nativeTitle == this.nativeTitle &&
          other.format == this.format &&
          other.episodeCount == this.episodeCount &&
          other.coverImageUrl == this.coverImageUrl &&
          other.coverImagePath == this.coverImagePath);
}

class SeriesCacheCompanion extends UpdateCompanion<CachedSeriesRow> {
  final Value<int> anilistId;
  final Value<String?> romaji;
  final Value<String?> english;
  final Value<String?> nativeTitle;
  final Value<String?> format;
  final Value<int?> episodeCount;
  final Value<String?> coverImageUrl;
  final Value<String?> coverImagePath;
  const SeriesCacheCompanion({
    this.anilistId = const Value.absent(),
    this.romaji = const Value.absent(),
    this.english = const Value.absent(),
    this.nativeTitle = const Value.absent(),
    this.format = const Value.absent(),
    this.episodeCount = const Value.absent(),
    this.coverImageUrl = const Value.absent(),
    this.coverImagePath = const Value.absent(),
  });
  SeriesCacheCompanion.insert({
    this.anilistId = const Value.absent(),
    this.romaji = const Value.absent(),
    this.english = const Value.absent(),
    this.nativeTitle = const Value.absent(),
    this.format = const Value.absent(),
    this.episodeCount = const Value.absent(),
    this.coverImageUrl = const Value.absent(),
    this.coverImagePath = const Value.absent(),
  });
  static Insertable<CachedSeriesRow> custom({
    Expression<int>? anilistId,
    Expression<String>? romaji,
    Expression<String>? english,
    Expression<String>? nativeTitle,
    Expression<String>? format,
    Expression<int>? episodeCount,
    Expression<String>? coverImageUrl,
    Expression<String>? coverImagePath,
  }) {
    return RawValuesInsertable({
      if (anilistId != null) 'anilist_id': anilistId,
      if (romaji != null) 'romaji': romaji,
      if (english != null) 'english': english,
      if (nativeTitle != null) 'native_title': nativeTitle,
      if (format != null) 'format': format,
      if (episodeCount != null) 'episode_count': episodeCount,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      if (coverImagePath != null) 'cover_image_path': coverImagePath,
    });
  }

  SeriesCacheCompanion copyWith({
    Value<int>? anilistId,
    Value<String?>? romaji,
    Value<String?>? english,
    Value<String?>? nativeTitle,
    Value<String?>? format,
    Value<int?>? episodeCount,
    Value<String?>? coverImageUrl,
    Value<String?>? coverImagePath,
  }) {
    return SeriesCacheCompanion(
      anilistId: anilistId ?? this.anilistId,
      romaji: romaji ?? this.romaji,
      english: english ?? this.english,
      nativeTitle: nativeTitle ?? this.nativeTitle,
      format: format ?? this.format,
      episodeCount: episodeCount ?? this.episodeCount,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      coverImagePath: coverImagePath ?? this.coverImagePath,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (anilistId.present) {
      map['anilist_id'] = Variable<int>(anilistId.value);
    }
    if (romaji.present) {
      map['romaji'] = Variable<String>(romaji.value);
    }
    if (english.present) {
      map['english'] = Variable<String>(english.value);
    }
    if (nativeTitle.present) {
      map['native_title'] = Variable<String>(nativeTitle.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (episodeCount.present) {
      map['episode_count'] = Variable<int>(episodeCount.value);
    }
    if (coverImageUrl.present) {
      map['cover_image_url'] = Variable<String>(coverImageUrl.value);
    }
    if (coverImagePath.present) {
      map['cover_image_path'] = Variable<String>(coverImagePath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesCacheCompanion(')
          ..write('anilistId: $anilistId, ')
          ..write('romaji: $romaji, ')
          ..write('english: $english, ')
          ..write('nativeTitle: $nativeTitle, ')
          ..write('format: $format, ')
          ..write('episodeCount: $episodeCount, ')
          ..write('coverImageUrl: $coverImageUrl, ')
          ..write('coverImagePath: $coverImagePath')
          ..write(')'))
        .toString();
  }
}

class $FileCacheTable extends FileCache
    with TableInfo<$FileCacheTable, CachedFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMsMeta = const VerificationMeta(
    'modifiedAtMs',
  );
  @override
  late final GeneratedColumn<int> modifiedAtMs = GeneratedColumn<int>(
    'modified_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anilistIdMeta = const VerificationMeta(
    'anilistId',
  );
  @override
  late final GeneratedColumn<int> anilistId = GeneratedColumn<int>(
    'anilist_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeNumberMeta = const VerificationMeta(
    'episodeNumber',
  );
  @override
  late final GeneratedColumn<int> episodeNumber = GeneratedColumn<int>(
    'episode_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parsedTitleMeta = const VerificationMeta(
    'parsedTitle',
  );
  @override
  late final GeneratedColumn<String> parsedTitle = GeneratedColumn<String>(
    'parsed_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matchScoreMeta = const VerificationMeta(
    'matchScore',
  );
  @override
  late final GeneratedColumn<double> matchScore = GeneratedColumn<double>(
    'match_score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _releaseGroupMeta = const VerificationMeta(
    'releaseGroup',
  );
  @override
  late final GeneratedColumn<String> releaseGroup = GeneratedColumn<String>(
    'release_group',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    fileSize,
    modifiedAtMs,
    anilistId,
    episodeNumber,
    parsedTitle,
    matchScore,
    releaseGroup,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('modified_at_ms')) {
      context.handle(
        _modifiedAtMsMeta,
        modifiedAtMs.isAcceptableOrUnknown(
          data['modified_at_ms']!,
          _modifiedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMsMeta);
    }
    if (data.containsKey('anilist_id')) {
      context.handle(
        _anilistIdMeta,
        anilistId.isAcceptableOrUnknown(data['anilist_id']!, _anilistIdMeta),
      );
    }
    if (data.containsKey('episode_number')) {
      context.handle(
        _episodeNumberMeta,
        episodeNumber.isAcceptableOrUnknown(
          data['episode_number']!,
          _episodeNumberMeta,
        ),
      );
    }
    if (data.containsKey('parsed_title')) {
      context.handle(
        _parsedTitleMeta,
        parsedTitle.isAcceptableOrUnknown(
          data['parsed_title']!,
          _parsedTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parsedTitleMeta);
    }
    if (data.containsKey('match_score')) {
      context.handle(
        _matchScoreMeta,
        matchScore.isAcceptableOrUnknown(data['match_score']!, _matchScoreMeta),
      );
    }
    if (data.containsKey('release_group')) {
      context.handle(
        _releaseGroupMeta,
        releaseGroup.isAcceptableOrUnknown(
          data['release_group']!,
          _releaseGroupMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  CachedFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFileRow(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      modifiedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_at_ms'],
      )!,
      anilistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anilist_id'],
      ),
      episodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_number'],
      ),
      parsedTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parsed_title'],
      )!,
      matchScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}match_score'],
      )!,
      releaseGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}release_group'],
      ),
    );
  }

  @override
  $FileCacheTable createAlias(String alias) {
    return $FileCacheTable(attachedDatabase, alias);
  }
}

class CachedFileRow extends DataClass implements Insertable<CachedFileRow> {
  final String path;
  final int fileSize;
  final int modifiedAtMs;
  final int? anilistId;
  final int? episodeNumber;
  final String parsedTitle;
  final double matchScore;
  final String? releaseGroup;
  const CachedFileRow({
    required this.path,
    required this.fileSize,
    required this.modifiedAtMs,
    this.anilistId,
    this.episodeNumber,
    required this.parsedTitle,
    required this.matchScore,
    this.releaseGroup,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['file_size'] = Variable<int>(fileSize);
    map['modified_at_ms'] = Variable<int>(modifiedAtMs);
    if (!nullToAbsent || anilistId != null) {
      map['anilist_id'] = Variable<int>(anilistId);
    }
    if (!nullToAbsent || episodeNumber != null) {
      map['episode_number'] = Variable<int>(episodeNumber);
    }
    map['parsed_title'] = Variable<String>(parsedTitle);
    map['match_score'] = Variable<double>(matchScore);
    if (!nullToAbsent || releaseGroup != null) {
      map['release_group'] = Variable<String>(releaseGroup);
    }
    return map;
  }

  FileCacheCompanion toCompanion(bool nullToAbsent) {
    return FileCacheCompanion(
      path: Value(path),
      fileSize: Value(fileSize),
      modifiedAtMs: Value(modifiedAtMs),
      anilistId: anilistId == null && nullToAbsent
          ? const Value.absent()
          : Value(anilistId),
      episodeNumber: episodeNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeNumber),
      parsedTitle: Value(parsedTitle),
      matchScore: Value(matchScore),
      releaseGroup: releaseGroup == null && nullToAbsent
          ? const Value.absent()
          : Value(releaseGroup),
    );
  }

  factory CachedFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFileRow(
      path: serializer.fromJson<String>(json['path']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      modifiedAtMs: serializer.fromJson<int>(json['modifiedAtMs']),
      anilistId: serializer.fromJson<int?>(json['anilistId']),
      episodeNumber: serializer.fromJson<int?>(json['episodeNumber']),
      parsedTitle: serializer.fromJson<String>(json['parsedTitle']),
      matchScore: serializer.fromJson<double>(json['matchScore']),
      releaseGroup: serializer.fromJson<String?>(json['releaseGroup']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'fileSize': serializer.toJson<int>(fileSize),
      'modifiedAtMs': serializer.toJson<int>(modifiedAtMs),
      'anilistId': serializer.toJson<int?>(anilistId),
      'episodeNumber': serializer.toJson<int?>(episodeNumber),
      'parsedTitle': serializer.toJson<String>(parsedTitle),
      'matchScore': serializer.toJson<double>(matchScore),
      'releaseGroup': serializer.toJson<String?>(releaseGroup),
    };
  }

  CachedFileRow copyWith({
    String? path,
    int? fileSize,
    int? modifiedAtMs,
    Value<int?> anilistId = const Value.absent(),
    Value<int?> episodeNumber = const Value.absent(),
    String? parsedTitle,
    double? matchScore,
    Value<String?> releaseGroup = const Value.absent(),
  }) => CachedFileRow(
    path: path ?? this.path,
    fileSize: fileSize ?? this.fileSize,
    modifiedAtMs: modifiedAtMs ?? this.modifiedAtMs,
    anilistId: anilistId.present ? anilistId.value : this.anilistId,
    episodeNumber: episodeNumber.present
        ? episodeNumber.value
        : this.episodeNumber,
    parsedTitle: parsedTitle ?? this.parsedTitle,
    matchScore: matchScore ?? this.matchScore,
    releaseGroup: releaseGroup.present ? releaseGroup.value : this.releaseGroup,
  );
  CachedFileRow copyWithCompanion(FileCacheCompanion data) {
    return CachedFileRow(
      path: data.path.present ? data.path.value : this.path,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      modifiedAtMs: data.modifiedAtMs.present
          ? data.modifiedAtMs.value
          : this.modifiedAtMs,
      anilistId: data.anilistId.present ? data.anilistId.value : this.anilistId,
      episodeNumber: data.episodeNumber.present
          ? data.episodeNumber.value
          : this.episodeNumber,
      parsedTitle: data.parsedTitle.present
          ? data.parsedTitle.value
          : this.parsedTitle,
      matchScore: data.matchScore.present
          ? data.matchScore.value
          : this.matchScore,
      releaseGroup: data.releaseGroup.present
          ? data.releaseGroup.value
          : this.releaseGroup,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFileRow(')
          ..write('path: $path, ')
          ..write('fileSize: $fileSize, ')
          ..write('modifiedAtMs: $modifiedAtMs, ')
          ..write('anilistId: $anilistId, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('parsedTitle: $parsedTitle, ')
          ..write('matchScore: $matchScore, ')
          ..write('releaseGroup: $releaseGroup')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    path,
    fileSize,
    modifiedAtMs,
    anilistId,
    episodeNumber,
    parsedTitle,
    matchScore,
    releaseGroup,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFileRow &&
          other.path == this.path &&
          other.fileSize == this.fileSize &&
          other.modifiedAtMs == this.modifiedAtMs &&
          other.anilistId == this.anilistId &&
          other.episodeNumber == this.episodeNumber &&
          other.parsedTitle == this.parsedTitle &&
          other.matchScore == this.matchScore &&
          other.releaseGroup == this.releaseGroup);
}

class FileCacheCompanion extends UpdateCompanion<CachedFileRow> {
  final Value<String> path;
  final Value<int> fileSize;
  final Value<int> modifiedAtMs;
  final Value<int?> anilistId;
  final Value<int?> episodeNumber;
  final Value<String> parsedTitle;
  final Value<double> matchScore;
  final Value<String?> releaseGroup;
  final Value<int> rowid;
  const FileCacheCompanion({
    this.path = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.modifiedAtMs = const Value.absent(),
    this.anilistId = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.parsedTitle = const Value.absent(),
    this.matchScore = const Value.absent(),
    this.releaseGroup = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FileCacheCompanion.insert({
    required String path,
    required int fileSize,
    required int modifiedAtMs,
    this.anilistId = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    required String parsedTitle,
    this.matchScore = const Value.absent(),
    this.releaseGroup = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       fileSize = Value(fileSize),
       modifiedAtMs = Value(modifiedAtMs),
       parsedTitle = Value(parsedTitle);
  static Insertable<CachedFileRow> custom({
    Expression<String>? path,
    Expression<int>? fileSize,
    Expression<int>? modifiedAtMs,
    Expression<int>? anilistId,
    Expression<int>? episodeNumber,
    Expression<String>? parsedTitle,
    Expression<double>? matchScore,
    Expression<String>? releaseGroup,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (fileSize != null) 'file_size': fileSize,
      if (modifiedAtMs != null) 'modified_at_ms': modifiedAtMs,
      if (anilistId != null) 'anilist_id': anilistId,
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (parsedTitle != null) 'parsed_title': parsedTitle,
      if (matchScore != null) 'match_score': matchScore,
      if (releaseGroup != null) 'release_group': releaseGroup,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FileCacheCompanion copyWith({
    Value<String>? path,
    Value<int>? fileSize,
    Value<int>? modifiedAtMs,
    Value<int?>? anilistId,
    Value<int?>? episodeNumber,
    Value<String>? parsedTitle,
    Value<double>? matchScore,
    Value<String?>? releaseGroup,
    Value<int>? rowid,
  }) {
    return FileCacheCompanion(
      path: path ?? this.path,
      fileSize: fileSize ?? this.fileSize,
      modifiedAtMs: modifiedAtMs ?? this.modifiedAtMs,
      anilistId: anilistId ?? this.anilistId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      parsedTitle: parsedTitle ?? this.parsedTitle,
      matchScore: matchScore ?? this.matchScore,
      releaseGroup: releaseGroup ?? this.releaseGroup,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (modifiedAtMs.present) {
      map['modified_at_ms'] = Variable<int>(modifiedAtMs.value);
    }
    if (anilistId.present) {
      map['anilist_id'] = Variable<int>(anilistId.value);
    }
    if (episodeNumber.present) {
      map['episode_number'] = Variable<int>(episodeNumber.value);
    }
    if (parsedTitle.present) {
      map['parsed_title'] = Variable<String>(parsedTitle.value);
    }
    if (matchScore.present) {
      map['match_score'] = Variable<double>(matchScore.value);
    }
    if (releaseGroup.present) {
      map['release_group'] = Variable<String>(releaseGroup.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileCacheCompanion(')
          ..write('path: $path, ')
          ..write('fileSize: $fileSize, ')
          ..write('modifiedAtMs: $modifiedAtMs, ')
          ..write('anilistId: $anilistId, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('parsedTitle: $parsedTitle, ')
          ..write('matchScore: $matchScore, ')
          ..write('releaseGroup: $releaseGroup, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryFoldersTable extends LibraryFolders
    with TableInfo<$LibraryFoldersTable, LibraryFolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryFoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMsMeta = const VerificationMeta(
    'addedAtMs',
  );
  @override
  late final GeneratedColumn<int> addedAtMs = GeneratedColumn<int>(
    'added_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [path, addedAtMs, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryFolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('added_at_ms')) {
      context.handle(
        _addedAtMsMeta,
        addedAtMs.isAcceptableOrUnknown(data['added_at_ms']!, _addedAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMsMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  LibraryFolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryFolderRow(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      addedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at_ms'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $LibraryFoldersTable createAlias(String alias) {
    return $LibraryFoldersTable(attachedDatabase, alias);
  }
}

class LibraryFolderRow extends DataClass
    implements Insertable<LibraryFolderRow> {
  final String path;
  final int addedAtMs;

  /// User-controllable rank (lower = higher priority). Stored so the order is
  /// stable across relaunch and expresses "A ranks above B" — a near-future
  /// feature (multi-source episodes) makes this order semantically meaningful
  /// (top = default playback source). No reorder UI / priority meaning yet.
  final int sortOrder;
  const LibraryFolderRow({
    required this.path,
    required this.addedAtMs,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['added_at_ms'] = Variable<int>(addedAtMs);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  LibraryFoldersCompanion toCompanion(bool nullToAbsent) {
    return LibraryFoldersCompanion(
      path: Value(path),
      addedAtMs: Value(addedAtMs),
      sortOrder: Value(sortOrder),
    );
  }

  factory LibraryFolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryFolderRow(
      path: serializer.fromJson<String>(json['path']),
      addedAtMs: serializer.fromJson<int>(json['addedAtMs']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'addedAtMs': serializer.toJson<int>(addedAtMs),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  LibraryFolderRow copyWith({String? path, int? addedAtMs, int? sortOrder}) =>
      LibraryFolderRow(
        path: path ?? this.path,
        addedAtMs: addedAtMs ?? this.addedAtMs,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  LibraryFolderRow copyWithCompanion(LibraryFoldersCompanion data) {
    return LibraryFolderRow(
      path: data.path.present ? data.path.value : this.path,
      addedAtMs: data.addedAtMs.present ? data.addedAtMs.value : this.addedAtMs,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFolderRow(')
          ..write('path: $path, ')
          ..write('addedAtMs: $addedAtMs, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, addedAtMs, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryFolderRow &&
          other.path == this.path &&
          other.addedAtMs == this.addedAtMs &&
          other.sortOrder == this.sortOrder);
}

class LibraryFoldersCompanion extends UpdateCompanion<LibraryFolderRow> {
  final Value<String> path;
  final Value<int> addedAtMs;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const LibraryFoldersCompanion({
    this.path = const Value.absent(),
    this.addedAtMs = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryFoldersCompanion.insert({
    required String path,
    required int addedAtMs,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       addedAtMs = Value(addedAtMs);
  static Insertable<LibraryFolderRow> custom({
    Expression<String>? path,
    Expression<int>? addedAtMs,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (addedAtMs != null) 'added_at_ms': addedAtMs,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryFoldersCompanion copyWith({
    Value<String>? path,
    Value<int>? addedAtMs,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return LibraryFoldersCompanion(
      path: path ?? this.path,
      addedAtMs: addedAtMs ?? this.addedAtMs,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (addedAtMs.present) {
      map['added_at_ms'] = Variable<int>(addedAtMs.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFoldersCompanion(')
          ..write('path: $path, ')
          ..write('addedAtMs: $addedAtMs, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MatchOverridesTable extends MatchOverrides
    with TableInfo<$MatchOverridesTable, MatchOverrideRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MatchOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMsMeta = const VerificationMeta(
    'modifiedAtMs',
  );
  @override
  late final GeneratedColumn<int> modifiedAtMs = GeneratedColumn<int>(
    'modified_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anilistIdMeta = const VerificationMeta(
    'anilistId',
  );
  @override
  late final GeneratedColumn<int> anilistId = GeneratedColumn<int>(
    'anilist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anchoredEpisodeMeta = const VerificationMeta(
    'anchoredEpisode',
  );
  @override
  late final GeneratedColumn<int> anchoredEpisode = GeneratedColumn<int>(
    'anchored_episode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _continuousOffsetMeta = const VerificationMeta(
    'continuousOffset',
  );
  @override
  late final GeneratedColumn<int> continuousOffset = GeneratedColumn<int>(
    'continuous_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _displayContinuousMeta = const VerificationMeta(
    'displayContinuous',
  );
  @override
  late final GeneratedColumn<bool> displayContinuous = GeneratedColumn<bool>(
    'display_continuous',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("display_continuous" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    fileSize,
    modifiedAtMs,
    anilistId,
    anchoredEpisode,
    continuousOffset,
    displayContinuous,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'match_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<MatchOverrideRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('modified_at_ms')) {
      context.handle(
        _modifiedAtMsMeta,
        modifiedAtMs.isAcceptableOrUnknown(
          data['modified_at_ms']!,
          _modifiedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMsMeta);
    }
    if (data.containsKey('anilist_id')) {
      context.handle(
        _anilistIdMeta,
        anilistId.isAcceptableOrUnknown(data['anilist_id']!, _anilistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_anilistIdMeta);
    }
    if (data.containsKey('anchored_episode')) {
      context.handle(
        _anchoredEpisodeMeta,
        anchoredEpisode.isAcceptableOrUnknown(
          data['anchored_episode']!,
          _anchoredEpisodeMeta,
        ),
      );
    }
    if (data.containsKey('continuous_offset')) {
      context.handle(
        _continuousOffsetMeta,
        continuousOffset.isAcceptableOrUnknown(
          data['continuous_offset']!,
          _continuousOffsetMeta,
        ),
      );
    }
    if (data.containsKey('display_continuous')) {
      context.handle(
        _displayContinuousMeta,
        displayContinuous.isAcceptableOrUnknown(
          data['display_continuous']!,
          _displayContinuousMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileSize, modifiedAtMs};
  @override
  MatchOverrideRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MatchOverrideRow(
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      modifiedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_at_ms'],
      )!,
      anilistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anilist_id'],
      )!,
      anchoredEpisode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anchored_episode'],
      ),
      continuousOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}continuous_offset'],
      )!,
      displayContinuous: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}display_continuous'],
      )!,
    );
  }

  @override
  $MatchOverridesTable createAlias(String alias) {
    return $MatchOverridesTable(attachedDatabase, alias);
  }
}

class MatchOverrideRow extends DataClass
    implements Insertable<MatchOverrideRow> {
  final int fileSize;
  final int modifiedAtMs;
  final int anilistId;
  final int? anchoredEpisode;
  final int continuousOffset;
  final bool displayContinuous;
  const MatchOverrideRow({
    required this.fileSize,
    required this.modifiedAtMs,
    required this.anilistId,
    this.anchoredEpisode,
    required this.continuousOffset,
    required this.displayContinuous,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_size'] = Variable<int>(fileSize);
    map['modified_at_ms'] = Variable<int>(modifiedAtMs);
    map['anilist_id'] = Variable<int>(anilistId);
    if (!nullToAbsent || anchoredEpisode != null) {
      map['anchored_episode'] = Variable<int>(anchoredEpisode);
    }
    map['continuous_offset'] = Variable<int>(continuousOffset);
    map['display_continuous'] = Variable<bool>(displayContinuous);
    return map;
  }

  MatchOverridesCompanion toCompanion(bool nullToAbsent) {
    return MatchOverridesCompanion(
      fileSize: Value(fileSize),
      modifiedAtMs: Value(modifiedAtMs),
      anilistId: Value(anilistId),
      anchoredEpisode: anchoredEpisode == null && nullToAbsent
          ? const Value.absent()
          : Value(anchoredEpisode),
      continuousOffset: Value(continuousOffset),
      displayContinuous: Value(displayContinuous),
    );
  }

  factory MatchOverrideRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MatchOverrideRow(
      fileSize: serializer.fromJson<int>(json['fileSize']),
      modifiedAtMs: serializer.fromJson<int>(json['modifiedAtMs']),
      anilistId: serializer.fromJson<int>(json['anilistId']),
      anchoredEpisode: serializer.fromJson<int?>(json['anchoredEpisode']),
      continuousOffset: serializer.fromJson<int>(json['continuousOffset']),
      displayContinuous: serializer.fromJson<bool>(json['displayContinuous']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileSize': serializer.toJson<int>(fileSize),
      'modifiedAtMs': serializer.toJson<int>(modifiedAtMs),
      'anilistId': serializer.toJson<int>(anilistId),
      'anchoredEpisode': serializer.toJson<int?>(anchoredEpisode),
      'continuousOffset': serializer.toJson<int>(continuousOffset),
      'displayContinuous': serializer.toJson<bool>(displayContinuous),
    };
  }

  MatchOverrideRow copyWith({
    int? fileSize,
    int? modifiedAtMs,
    int? anilistId,
    Value<int?> anchoredEpisode = const Value.absent(),
    int? continuousOffset,
    bool? displayContinuous,
  }) => MatchOverrideRow(
    fileSize: fileSize ?? this.fileSize,
    modifiedAtMs: modifiedAtMs ?? this.modifiedAtMs,
    anilistId: anilistId ?? this.anilistId,
    anchoredEpisode: anchoredEpisode.present
        ? anchoredEpisode.value
        : this.anchoredEpisode,
    continuousOffset: continuousOffset ?? this.continuousOffset,
    displayContinuous: displayContinuous ?? this.displayContinuous,
  );
  MatchOverrideRow copyWithCompanion(MatchOverridesCompanion data) {
    return MatchOverrideRow(
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      modifiedAtMs: data.modifiedAtMs.present
          ? data.modifiedAtMs.value
          : this.modifiedAtMs,
      anilistId: data.anilistId.present ? data.anilistId.value : this.anilistId,
      anchoredEpisode: data.anchoredEpisode.present
          ? data.anchoredEpisode.value
          : this.anchoredEpisode,
      continuousOffset: data.continuousOffset.present
          ? data.continuousOffset.value
          : this.continuousOffset,
      displayContinuous: data.displayContinuous.present
          ? data.displayContinuous.value
          : this.displayContinuous,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MatchOverrideRow(')
          ..write('fileSize: $fileSize, ')
          ..write('modifiedAtMs: $modifiedAtMs, ')
          ..write('anilistId: $anilistId, ')
          ..write('anchoredEpisode: $anchoredEpisode, ')
          ..write('continuousOffset: $continuousOffset, ')
          ..write('displayContinuous: $displayContinuous')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    fileSize,
    modifiedAtMs,
    anilistId,
    anchoredEpisode,
    continuousOffset,
    displayContinuous,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MatchOverrideRow &&
          other.fileSize == this.fileSize &&
          other.modifiedAtMs == this.modifiedAtMs &&
          other.anilistId == this.anilistId &&
          other.anchoredEpisode == this.anchoredEpisode &&
          other.continuousOffset == this.continuousOffset &&
          other.displayContinuous == this.displayContinuous);
}

class MatchOverridesCompanion extends UpdateCompanion<MatchOverrideRow> {
  final Value<int> fileSize;
  final Value<int> modifiedAtMs;
  final Value<int> anilistId;
  final Value<int?> anchoredEpisode;
  final Value<int> continuousOffset;
  final Value<bool> displayContinuous;
  final Value<int> rowid;
  const MatchOverridesCompanion({
    this.fileSize = const Value.absent(),
    this.modifiedAtMs = const Value.absent(),
    this.anilistId = const Value.absent(),
    this.anchoredEpisode = const Value.absent(),
    this.continuousOffset = const Value.absent(),
    this.displayContinuous = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MatchOverridesCompanion.insert({
    required int fileSize,
    required int modifiedAtMs,
    required int anilistId,
    this.anchoredEpisode = const Value.absent(),
    this.continuousOffset = const Value.absent(),
    this.displayContinuous = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : fileSize = Value(fileSize),
       modifiedAtMs = Value(modifiedAtMs),
       anilistId = Value(anilistId);
  static Insertable<MatchOverrideRow> custom({
    Expression<int>? fileSize,
    Expression<int>? modifiedAtMs,
    Expression<int>? anilistId,
    Expression<int>? anchoredEpisode,
    Expression<int>? continuousOffset,
    Expression<bool>? displayContinuous,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fileSize != null) 'file_size': fileSize,
      if (modifiedAtMs != null) 'modified_at_ms': modifiedAtMs,
      if (anilistId != null) 'anilist_id': anilistId,
      if (anchoredEpisode != null) 'anchored_episode': anchoredEpisode,
      if (continuousOffset != null) 'continuous_offset': continuousOffset,
      if (displayContinuous != null) 'display_continuous': displayContinuous,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MatchOverridesCompanion copyWith({
    Value<int>? fileSize,
    Value<int>? modifiedAtMs,
    Value<int>? anilistId,
    Value<int?>? anchoredEpisode,
    Value<int>? continuousOffset,
    Value<bool>? displayContinuous,
    Value<int>? rowid,
  }) {
    return MatchOverridesCompanion(
      fileSize: fileSize ?? this.fileSize,
      modifiedAtMs: modifiedAtMs ?? this.modifiedAtMs,
      anilistId: anilistId ?? this.anilistId,
      anchoredEpisode: anchoredEpisode ?? this.anchoredEpisode,
      continuousOffset: continuousOffset ?? this.continuousOffset,
      displayContinuous: displayContinuous ?? this.displayContinuous,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (modifiedAtMs.present) {
      map['modified_at_ms'] = Variable<int>(modifiedAtMs.value);
    }
    if (anilistId.present) {
      map['anilist_id'] = Variable<int>(anilistId.value);
    }
    if (anchoredEpisode.present) {
      map['anchored_episode'] = Variable<int>(anchoredEpisode.value);
    }
    if (continuousOffset.present) {
      map['continuous_offset'] = Variable<int>(continuousOffset.value);
    }
    if (displayContinuous.present) {
      map['display_continuous'] = Variable<bool>(displayContinuous.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MatchOverridesCompanion(')
          ..write('fileSize: $fileSize, ')
          ..write('modifiedAtMs: $modifiedAtMs, ')
          ..write('anilistId: $anilistId, ')
          ..write('anchoredEpisode: $anchoredEpisode, ')
          ..write('continuousOffset: $continuousOffset, ')
          ..write('displayContinuous: $displayContinuous, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $SeriesCacheTable seriesCache = $SeriesCacheTable(this);
  late final $FileCacheTable fileCache = $FileCacheTable(this);
  late final $LibraryFoldersTable libraryFolders = $LibraryFoldersTable(this);
  late final $MatchOverridesTable matchOverrides = $MatchOverridesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    seriesCache,
    fileCache,
    libraryFolders,
    matchOverrides,
  ];
}

typedef $$SeriesCacheTableCreateCompanionBuilder =
    SeriesCacheCompanion Function({
      Value<int> anilistId,
      Value<String?> romaji,
      Value<String?> english,
      Value<String?> nativeTitle,
      Value<String?> format,
      Value<int?> episodeCount,
      Value<String?> coverImageUrl,
      Value<String?> coverImagePath,
    });
typedef $$SeriesCacheTableUpdateCompanionBuilder =
    SeriesCacheCompanion Function({
      Value<int> anilistId,
      Value<String?> romaji,
      Value<String?> english,
      Value<String?> nativeTitle,
      Value<String?> format,
      Value<int?> episodeCount,
      Value<String?> coverImageUrl,
      Value<String?> coverImagePath,
    });

class $$SeriesCacheTableFilterComposer
    extends Composer<_$CacheDatabase, $SeriesCacheTable> {
  $$SeriesCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get anilistId => $composableBuilder(
    column: $table.anilistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get romaji => $composableBuilder(
    column: $table.romaji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get english => $composableBuilder(
    column: $table.english,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nativeTitle => $composableBuilder(
    column: $table.nativeTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImageUrl => $composableBuilder(
    column: $table.coverImageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesCacheTableOrderingComposer
    extends Composer<_$CacheDatabase, $SeriesCacheTable> {
  $$SeriesCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get anilistId => $composableBuilder(
    column: $table.anilistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get romaji => $composableBuilder(
    column: $table.romaji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get english => $composableBuilder(
    column: $table.english,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nativeTitle => $composableBuilder(
    column: $table.nativeTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImageUrl => $composableBuilder(
    column: $table.coverImageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesCacheTableAnnotationComposer
    extends Composer<_$CacheDatabase, $SeriesCacheTable> {
  $$SeriesCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get anilistId =>
      $composableBuilder(column: $table.anilistId, builder: (column) => column);

  GeneratedColumn<String> get romaji =>
      $composableBuilder(column: $table.romaji, builder: (column) => column);

  GeneratedColumn<String> get english =>
      $composableBuilder(column: $table.english, builder: (column) => column);

  GeneratedColumn<String> get nativeTitle => $composableBuilder(
    column: $table.nativeTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverImageUrl => $composableBuilder(
    column: $table.coverImageUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => column,
  );
}

class $$SeriesCacheTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $SeriesCacheTable,
          CachedSeriesRow,
          $$SeriesCacheTableFilterComposer,
          $$SeriesCacheTableOrderingComposer,
          $$SeriesCacheTableAnnotationComposer,
          $$SeriesCacheTableCreateCompanionBuilder,
          $$SeriesCacheTableUpdateCompanionBuilder,
          (
            CachedSeriesRow,
            BaseReferences<_$CacheDatabase, $SeriesCacheTable, CachedSeriesRow>,
          ),
          CachedSeriesRow,
          PrefetchHooks Function()
        > {
  $$SeriesCacheTableTableManager(_$CacheDatabase db, $SeriesCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> anilistId = const Value.absent(),
                Value<String?> romaji = const Value.absent(),
                Value<String?> english = const Value.absent(),
                Value<String?> nativeTitle = const Value.absent(),
                Value<String?> format = const Value.absent(),
                Value<int?> episodeCount = const Value.absent(),
                Value<String?> coverImageUrl = const Value.absent(),
                Value<String?> coverImagePath = const Value.absent(),
              }) => SeriesCacheCompanion(
                anilistId: anilistId,
                romaji: romaji,
                english: english,
                nativeTitle: nativeTitle,
                format: format,
                episodeCount: episodeCount,
                coverImageUrl: coverImageUrl,
                coverImagePath: coverImagePath,
              ),
          createCompanionCallback:
              ({
                Value<int> anilistId = const Value.absent(),
                Value<String?> romaji = const Value.absent(),
                Value<String?> english = const Value.absent(),
                Value<String?> nativeTitle = const Value.absent(),
                Value<String?> format = const Value.absent(),
                Value<int?> episodeCount = const Value.absent(),
                Value<String?> coverImageUrl = const Value.absent(),
                Value<String?> coverImagePath = const Value.absent(),
              }) => SeriesCacheCompanion.insert(
                anilistId: anilistId,
                romaji: romaji,
                english: english,
                nativeTitle: nativeTitle,
                format: format,
                episodeCount: episodeCount,
                coverImageUrl: coverImageUrl,
                coverImagePath: coverImagePath,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $SeriesCacheTable,
      CachedSeriesRow,
      $$SeriesCacheTableFilterComposer,
      $$SeriesCacheTableOrderingComposer,
      $$SeriesCacheTableAnnotationComposer,
      $$SeriesCacheTableCreateCompanionBuilder,
      $$SeriesCacheTableUpdateCompanionBuilder,
      (
        CachedSeriesRow,
        BaseReferences<_$CacheDatabase, $SeriesCacheTable, CachedSeriesRow>,
      ),
      CachedSeriesRow,
      PrefetchHooks Function()
    >;
typedef $$FileCacheTableCreateCompanionBuilder =
    FileCacheCompanion Function({
      required String path,
      required int fileSize,
      required int modifiedAtMs,
      Value<int?> anilistId,
      Value<int?> episodeNumber,
      required String parsedTitle,
      Value<double> matchScore,
      Value<String?> releaseGroup,
      Value<int> rowid,
    });
typedef $$FileCacheTableUpdateCompanionBuilder =
    FileCacheCompanion Function({
      Value<String> path,
      Value<int> fileSize,
      Value<int> modifiedAtMs,
      Value<int?> anilistId,
      Value<int?> episodeNumber,
      Value<String> parsedTitle,
      Value<double> matchScore,
      Value<String?> releaseGroup,
      Value<int> rowid,
    });

class $$FileCacheTableFilterComposer
    extends Composer<_$CacheDatabase, $FileCacheTable> {
  $$FileCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedAtMs => $composableBuilder(
    column: $table.modifiedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anilistId => $composableBuilder(
    column: $table.anilistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parsedTitle => $composableBuilder(
    column: $table.parsedTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get matchScore => $composableBuilder(
    column: $table.matchScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get releaseGroup => $composableBuilder(
    column: $table.releaseGroup,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FileCacheTableOrderingComposer
    extends Composer<_$CacheDatabase, $FileCacheTable> {
  $$FileCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedAtMs => $composableBuilder(
    column: $table.modifiedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anilistId => $composableBuilder(
    column: $table.anilistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parsedTitle => $composableBuilder(
    column: $table.parsedTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get matchScore => $composableBuilder(
    column: $table.matchScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get releaseGroup => $composableBuilder(
    column: $table.releaseGroup,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FileCacheTableAnnotationComposer
    extends Composer<_$CacheDatabase, $FileCacheTable> {
  $$FileCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<int> get modifiedAtMs => $composableBuilder(
    column: $table.modifiedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get anilistId =>
      $composableBuilder(column: $table.anilistId, builder: (column) => column);

  GeneratedColumn<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parsedTitle => $composableBuilder(
    column: $table.parsedTitle,
    builder: (column) => column,
  );

  GeneratedColumn<double> get matchScore => $composableBuilder(
    column: $table.matchScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get releaseGroup => $composableBuilder(
    column: $table.releaseGroup,
    builder: (column) => column,
  );
}

class $$FileCacheTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $FileCacheTable,
          CachedFileRow,
          $$FileCacheTableFilterComposer,
          $$FileCacheTableOrderingComposer,
          $$FileCacheTableAnnotationComposer,
          $$FileCacheTableCreateCompanionBuilder,
          $$FileCacheTableUpdateCompanionBuilder,
          (
            CachedFileRow,
            BaseReferences<_$CacheDatabase, $FileCacheTable, CachedFileRow>,
          ),
          CachedFileRow,
          PrefetchHooks Function()
        > {
  $$FileCacheTableTableManager(_$CacheDatabase db, $FileCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<int> modifiedAtMs = const Value.absent(),
                Value<int?> anilistId = const Value.absent(),
                Value<int?> episodeNumber = const Value.absent(),
                Value<String> parsedTitle = const Value.absent(),
                Value<double> matchScore = const Value.absent(),
                Value<String?> releaseGroup = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileCacheCompanion(
                path: path,
                fileSize: fileSize,
                modifiedAtMs: modifiedAtMs,
                anilistId: anilistId,
                episodeNumber: episodeNumber,
                parsedTitle: parsedTitle,
                matchScore: matchScore,
                releaseGroup: releaseGroup,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required int fileSize,
                required int modifiedAtMs,
                Value<int?> anilistId = const Value.absent(),
                Value<int?> episodeNumber = const Value.absent(),
                required String parsedTitle,
                Value<double> matchScore = const Value.absent(),
                Value<String?> releaseGroup = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileCacheCompanion.insert(
                path: path,
                fileSize: fileSize,
                modifiedAtMs: modifiedAtMs,
                anilistId: anilistId,
                episodeNumber: episodeNumber,
                parsedTitle: parsedTitle,
                matchScore: matchScore,
                releaseGroup: releaseGroup,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FileCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $FileCacheTable,
      CachedFileRow,
      $$FileCacheTableFilterComposer,
      $$FileCacheTableOrderingComposer,
      $$FileCacheTableAnnotationComposer,
      $$FileCacheTableCreateCompanionBuilder,
      $$FileCacheTableUpdateCompanionBuilder,
      (
        CachedFileRow,
        BaseReferences<_$CacheDatabase, $FileCacheTable, CachedFileRow>,
      ),
      CachedFileRow,
      PrefetchHooks Function()
    >;
typedef $$LibraryFoldersTableCreateCompanionBuilder =
    LibraryFoldersCompanion Function({
      required String path,
      required int addedAtMs,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$LibraryFoldersTableUpdateCompanionBuilder =
    LibraryFoldersCompanion Function({
      Value<String> path,
      Value<int> addedAtMs,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$LibraryFoldersTableFilterComposer
    extends Composer<_$CacheDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAtMs => $composableBuilder(
    column: $table.addedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryFoldersTableOrderingComposer
    extends Composer<_$CacheDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAtMs => $composableBuilder(
    column: $table.addedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryFoldersTableAnnotationComposer
    extends Composer<_$CacheDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get addedAtMs =>
      $composableBuilder(column: $table.addedAtMs, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$LibraryFoldersTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $LibraryFoldersTable,
          LibraryFolderRow,
          $$LibraryFoldersTableFilterComposer,
          $$LibraryFoldersTableOrderingComposer,
          $$LibraryFoldersTableAnnotationComposer,
          $$LibraryFoldersTableCreateCompanionBuilder,
          $$LibraryFoldersTableUpdateCompanionBuilder,
          (
            LibraryFolderRow,
            BaseReferences<
              _$CacheDatabase,
              $LibraryFoldersTable,
              LibraryFolderRow
            >,
          ),
          LibraryFolderRow,
          PrefetchHooks Function()
        > {
  $$LibraryFoldersTableTableManager(
    _$CacheDatabase db,
    $LibraryFoldersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryFoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryFoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryFoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<int> addedAtMs = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryFoldersCompanion(
                path: path,
                addedAtMs: addedAtMs,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required int addedAtMs,
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryFoldersCompanion.insert(
                path: path,
                addedAtMs: addedAtMs,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryFoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $LibraryFoldersTable,
      LibraryFolderRow,
      $$LibraryFoldersTableFilterComposer,
      $$LibraryFoldersTableOrderingComposer,
      $$LibraryFoldersTableAnnotationComposer,
      $$LibraryFoldersTableCreateCompanionBuilder,
      $$LibraryFoldersTableUpdateCompanionBuilder,
      (
        LibraryFolderRow,
        BaseReferences<_$CacheDatabase, $LibraryFoldersTable, LibraryFolderRow>,
      ),
      LibraryFolderRow,
      PrefetchHooks Function()
    >;
typedef $$MatchOverridesTableCreateCompanionBuilder =
    MatchOverridesCompanion Function({
      required int fileSize,
      required int modifiedAtMs,
      required int anilistId,
      Value<int?> anchoredEpisode,
      Value<int> continuousOffset,
      Value<bool> displayContinuous,
      Value<int> rowid,
    });
typedef $$MatchOverridesTableUpdateCompanionBuilder =
    MatchOverridesCompanion Function({
      Value<int> fileSize,
      Value<int> modifiedAtMs,
      Value<int> anilistId,
      Value<int?> anchoredEpisode,
      Value<int> continuousOffset,
      Value<bool> displayContinuous,
      Value<int> rowid,
    });

class $$MatchOverridesTableFilterComposer
    extends Composer<_$CacheDatabase, $MatchOverridesTable> {
  $$MatchOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedAtMs => $composableBuilder(
    column: $table.modifiedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anilistId => $composableBuilder(
    column: $table.anilistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anchoredEpisode => $composableBuilder(
    column: $table.anchoredEpisode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get continuousOffset => $composableBuilder(
    column: $table.continuousOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get displayContinuous => $composableBuilder(
    column: $table.displayContinuous,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MatchOverridesTableOrderingComposer
    extends Composer<_$CacheDatabase, $MatchOverridesTable> {
  $$MatchOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedAtMs => $composableBuilder(
    column: $table.modifiedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anilistId => $composableBuilder(
    column: $table.anilistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anchoredEpisode => $composableBuilder(
    column: $table.anchoredEpisode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get continuousOffset => $composableBuilder(
    column: $table.continuousOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get displayContinuous => $composableBuilder(
    column: $table.displayContinuous,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MatchOverridesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $MatchOverridesTable> {
  $$MatchOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<int> get modifiedAtMs => $composableBuilder(
    column: $table.modifiedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get anilistId =>
      $composableBuilder(column: $table.anilistId, builder: (column) => column);

  GeneratedColumn<int> get anchoredEpisode => $composableBuilder(
    column: $table.anchoredEpisode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get continuousOffset => $composableBuilder(
    column: $table.continuousOffset,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get displayContinuous => $composableBuilder(
    column: $table.displayContinuous,
    builder: (column) => column,
  );
}

class $$MatchOverridesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $MatchOverridesTable,
          MatchOverrideRow,
          $$MatchOverridesTableFilterComposer,
          $$MatchOverridesTableOrderingComposer,
          $$MatchOverridesTableAnnotationComposer,
          $$MatchOverridesTableCreateCompanionBuilder,
          $$MatchOverridesTableUpdateCompanionBuilder,
          (
            MatchOverrideRow,
            BaseReferences<
              _$CacheDatabase,
              $MatchOverridesTable,
              MatchOverrideRow
            >,
          ),
          MatchOverrideRow,
          PrefetchHooks Function()
        > {
  $$MatchOverridesTableTableManager(
    _$CacheDatabase db,
    $MatchOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MatchOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MatchOverridesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MatchOverridesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> fileSize = const Value.absent(),
                Value<int> modifiedAtMs = const Value.absent(),
                Value<int> anilistId = const Value.absent(),
                Value<int?> anchoredEpisode = const Value.absent(),
                Value<int> continuousOffset = const Value.absent(),
                Value<bool> displayContinuous = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MatchOverridesCompanion(
                fileSize: fileSize,
                modifiedAtMs: modifiedAtMs,
                anilistId: anilistId,
                anchoredEpisode: anchoredEpisode,
                continuousOffset: continuousOffset,
                displayContinuous: displayContinuous,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int fileSize,
                required int modifiedAtMs,
                required int anilistId,
                Value<int?> anchoredEpisode = const Value.absent(),
                Value<int> continuousOffset = const Value.absent(),
                Value<bool> displayContinuous = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MatchOverridesCompanion.insert(
                fileSize: fileSize,
                modifiedAtMs: modifiedAtMs,
                anilistId: anilistId,
                anchoredEpisode: anchoredEpisode,
                continuousOffset: continuousOffset,
                displayContinuous: displayContinuous,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MatchOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $MatchOverridesTable,
      MatchOverrideRow,
      $$MatchOverridesTableFilterComposer,
      $$MatchOverridesTableOrderingComposer,
      $$MatchOverridesTableAnnotationComposer,
      $$MatchOverridesTableCreateCompanionBuilder,
      $$MatchOverridesTableUpdateCompanionBuilder,
      (
        MatchOverrideRow,
        BaseReferences<_$CacheDatabase, $MatchOverridesTable, MatchOverrideRow>,
      ),
      MatchOverrideRow,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$SeriesCacheTableTableManager get seriesCache =>
      $$SeriesCacheTableTableManager(_db, _db.seriesCache);
  $$FileCacheTableTableManager get fileCache =>
      $$FileCacheTableTableManager(_db, _db.fileCache);
  $$LibraryFoldersTableTableManager get libraryFolders =>
      $$LibraryFoldersTableTableManager(_db, _db.libraryFolders);
  $$MatchOverridesTableTableManager get matchOverrides =>
      $$MatchOverridesTableTableManager(_db, _db.matchOverrides);
}
