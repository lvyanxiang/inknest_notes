import 'package:audioplayers/audioplayers.dart';

abstract class NotebookAudioPlayer {
  Stream<Duration> get positionChanges;

  Stream<Duration> get durationChanges;

  Stream<bool> get playingChanges;

  Stream<void> get completions;

  Future<void> playFile(String path);

  Future<void> resume();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> stop();

  Future<void> dispose();
}

class DeviceNotebookAudioPlayer implements NotebookAudioPlayer {
  DeviceNotebookAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionChanges => _player.onPositionChanged;

  @override
  Stream<Duration> get durationChanges => _player.onDurationChanged;

  @override
  Stream<bool> get playingChanges =>
      _player.onPlayerStateChanged.map((state) => state == PlayerState.playing);

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Future<void> playFile(String path) {
    return _player.play(DeviceFileSource(path));
  }

  @override
  Future<void> resume() {
    return _player.resume();
  }

  @override
  Future<void> pause() {
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) {
    return _player.seek(position);
  }

  @override
  Future<void> stop() {
    return _player.stop();
  }

  @override
  Future<void> dispose() {
    return _player.dispose();
  }
}
