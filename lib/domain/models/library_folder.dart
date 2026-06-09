import 'package:equatable/equatable.dart';

/// A folder the user has pointed AniLocal at. The scanner walks every
/// registered [LibraryFolder]. Identified by its [path].
class LibraryFolder extends Equatable {
  const LibraryFolder({required this.path});

  final String path;

  @override
  List<Object?> get props => [path];
}
