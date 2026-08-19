import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/ui/settings/sources_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory stand-in for the folder side of [LibraryRepository].
///
/// Only the three folder methods the Sources tab touches are implemented — the
/// rest of the interface would be noise here, and `Fake` makes any accidental
/// call throw loudly rather than quietly return null.
class FakeSourcesRepository extends Fake implements LibraryRepository {
  FakeSourcesRepository([List<String> paths = const []]) : _paths = [...paths];

  final List<String> _paths;

  /// The persisted priority order, top first — what `reorderFolders` wrote.
  List<String> get order => List.unmodifiable(_paths);

  @override
  Future<List<LibraryFolder>> watchedFolders() async => [
    for (final p in _paths) LibraryFolder(path: p),
  ];

  @override
  Future<void> removeFolder(LibraryFolder folder) async =>
      _paths.remove(folder.path);

  @override
  Future<void> reorderFolders(List<LibraryFolder> orderedFolders) async {
    _paths
      ..clear()
      ..addAll([for (final f in orderedFolders) f.path]);
  }
}

/// A [SourcesActions] over [FakeSourcesRepository], with an add-folder hook a
/// test can point wherever it needs.
SourcesActions fakeSourcesActions(
  FakeSourcesRepository repository, {
  Future<({bool added, String? deniedLabel})> Function()? onAddFolder,
}) => SourcesActions(
  repository: repository,
  onAddFolder: onAddFolder ?? () async => (added: false, deniedLabel: null),
  onOpenAccessSettings: () async => false,
);
