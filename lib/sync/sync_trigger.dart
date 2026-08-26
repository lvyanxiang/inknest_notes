import 'dart:async';

/// Bridges successful local persistence to the foreground sync scheduler.
class SyncTriggerController {
  final StreamController<void> _controller = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get requests => _controller.stream;

  void request() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  Future<void> dispose() => _controller.close();
}
