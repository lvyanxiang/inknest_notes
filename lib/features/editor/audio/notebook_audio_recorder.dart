import 'package:record/record.dart';

abstract class NotebookAudioRecorder {
  Future<bool> requestPermission();

  Future<void> start(String path);

  Future<void> pause();

  Future<void> resume();

  Future<String?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

class DeviceNotebookAudioRecorder implements NotebookAudioRecorder {
  DeviceNotebookAudioRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> requestPermission() {
    return _recorder.hasPermission();
  }

  @override
  Future<void> start(String path) {
    return _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<void> pause() {
    return _recorder.pause();
  }

  @override
  Future<void> resume() {
    return _recorder.resume();
  }

  @override
  Future<String?> stop() {
    return _recorder.stop();
  }

  @override
  Future<void> cancel() {
    return _recorder.cancel();
  }

  @override
  Future<void> dispose() {
    return _recorder.dispose();
  }
}
