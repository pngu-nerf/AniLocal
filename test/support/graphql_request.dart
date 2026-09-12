import 'dart:convert';

import 'package:http/http.dart' as http;

/// The `variables` object of a captured GraphQL POST, typed.
///
/// Fifteen tests used to reach into `jsonDecode(req.body)['variables'][...]`
/// through `dynamic`; one typed reader means a malformed capture fails here,
/// with a cast error naming the test, rather than as a `NoSuchMethodError`
/// three calls later.
Map<String, dynamic> graphqlVariables(http.Request req) =>
    (jsonDecode(req.body) as Map<String, dynamic>)['variables']
        as Map<String, dynamic>;
