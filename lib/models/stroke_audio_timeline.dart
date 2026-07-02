import 'package:inknest_notes/models/note_audio_recording.dart';
import 'package:inknest_notes/models/stroke.dart';

enum StrokeAudioPlaybackState { unlinked, upcoming, current, reached }

class StrokeAudioTimeline {
  const StrokeAudioTimeline._();

  static StrokeAudioPlaybackState stateFor({
    required Stroke stroke,
    required NoteAudioRecording recording,
    required Duration playbackPosition,
  }) {
    if (stroke.points.isEmpty) {
      return StrokeAudioPlaybackState.unlinked;
    }

    final recordingStart = recording.createdAt;
    final recordingEnd = recordingStart.add(recording.duration);
    final strokeStart = stroke.points.first.time;
    final strokeEnd = stroke.points.last.time;
    const tolerance = Duration(milliseconds: 500);

    if (strokeStart.isBefore(recordingStart.subtract(tolerance)) ||
        strokeStart.isAfter(recordingEnd.add(tolerance))) {
      return StrokeAudioPlaybackState.unlinked;
    }

    final playbackTime = recordingStart.add(playbackPosition);
    if (playbackTime.isBefore(strokeStart)) {
      return StrokeAudioPlaybackState.upcoming;
    }

    final highlightEnd = strokeEnd.add(const Duration(milliseconds: 900));
    if (!playbackTime.isAfter(highlightEnd)) {
      return StrokeAudioPlaybackState.current;
    }

    return StrokeAudioPlaybackState.reached;
  }

  static int linkedStrokeCount({
    required Iterable<Stroke> strokes,
    required NoteAudioRecording recording,
  }) {
    return strokes
        .where(
          (stroke) =>
              stateFor(
                stroke: stroke,
                recording: recording,
                playbackPosition: Duration.zero,
              ) !=
              StrokeAudioPlaybackState.unlinked,
        )
        .length;
  }
}
