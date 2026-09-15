/// Bytes that pass the cover store's image check: a JPEG SOI marker and an
/// APP0 header, twelve bytes in all (the check reads twelve). Every scan
/// fixture that serves "art" serves these; an arbitrary `[1, 2, 3]` used to
/// pass, and an HTML error page along with it.
const List<int> kFakeJpeg = [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
];

/// Bytes that are NOT an image — what a captive portal or an error page
/// returns with a 200.
const List<int> kFakeHtml = [
  0x3C, 0x68, 0x74, 0x6D, 0x6C, 0x3E, 0x3C, 0x62, 0x6F, 0x64, 0x79, 0x3E, //
];
