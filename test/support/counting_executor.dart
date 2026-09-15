import 'package:drift/drift.dart';

/// Counts every statement the database runs and how long each took, so a test
/// can say "this read issued N selects" — an exact number, unlike a timing.
///
/// Attach with `NativeDatabase.memory().interceptWith(counter)`. [reset]
/// between measurements; [summary] for the report line.
class CountingInterceptor extends QueryInterceptor {
  int selects = 0;
  int inserts = 0;
  int updates = 0;
  int deletes = 0;
  int customs = 0;
  int transactions = 0;
  Duration busy = Duration.zero;

  /// Statements by their first two words ("SELECT file_cache" is not
  /// available — drift generates `SELECT * FROM "file_cache"`, so the table
  /// is the fourth token), counted so a report can name the hot tables.
  final Map<String, int> byTable = {};

  int get statements => selects + inserts + updates + deletes + customs;

  void reset() {
    selects = inserts = updates = deletes = customs = transactions = 0;
    busy = Duration.zero;
    byTable.clear();
  }

  String summary() =>
      '$statements statements ($selects select, $inserts insert, $updates '
      'update, $deletes delete, $customs custom; $transactions tx; '
      '${busy.inMilliseconds}ms in SQLite)';

  void _note(String statement) {
    final m = RegExp(
      r'FROM\s+"?(\w+)"?',
      caseSensitive: false,
    ).firstMatch(statement);
    final table = m?.group(1) ?? statement.split(' ').take(2).join(' ');
    byTable[table] = (byTable[table] ?? 0) + 1;
  }

  Future<T> _timed<T>(Future<T> Function() run) async {
    final sw = Stopwatch()..start();
    try {
      return await run();
    } finally {
      busy += sw.elapsed;
    }
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    _note(statement);
    return _timed(() => super.runSelect(executor, statement, args));
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    inserts++;
    return _timed(() => super.runInsert(executor, statement, args));
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    updates++;
    return _timed(() => super.runUpdate(executor, statement, args));
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    deletes++;
    return _timed(() => super.runDelete(executor, statement, args));
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    customs++;
    _note(statement);
    return _timed(() => super.runCustom(executor, statement, args));
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    inserts += statements.arguments.length;
    return _timed(() => super.runBatched(executor, statements));
  }
}
