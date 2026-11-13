/// A path on shared storage that the app may treat as the user's own file or folder:
/// not another app's private area, and no ".." that could lead out of /storage.
///
/// The native IncomingUriPolicy asks a narrower question on canonical paths (is this one of
/// our own private files?), so it stays its own rule.
bool isSharedStoragePath(String path) =>
    path.startsWith('/storage/') &&
    !path.split('/').contains('..') &&
    !path.contains('/Android/data/') &&
    !path.contains('/Android/obb/');
