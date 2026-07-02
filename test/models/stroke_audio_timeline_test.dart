import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_audio_recording.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_audio_timeline.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  final recordingStart = DateTime.utc(2026, 7, 2, 8);
  final recording = NoteAudioRecording(
    id: 'recording-1',
    title: 'Recording 1',
    assetPath: 'assets/audio/recording-1.m4a',
    createdAt: recordingStart,
    durationMilliseconds: 10000,
  );

  test('maps recording playback time to linked stroke states', () {
    final linkedStroke = _stroke(
      id: 'linked',
      start: recordingStart.add(const Duration(seconds: 4)),
      end: recordingStart.add(const Duration(milliseconds: 4300)),
    );
    final unlinkedStroke = _stroke(
      id: 'unlinked',
      start: recordingStart.subtract(const Duration(seconds: 2)),
    );

    expect(
      StrokeAudioTimeline.stateFor(
        stroke: unlinkedStroke,
        recording: recording,
        playbackPosition: Duration.zero,
      ),
      StrokeAudioPlaybackState.unlinked,
    );
    expect(
      StrokeAudioTimeline.stateFor(
        stroke: linkedStroke,
        recording: recording,
        playbackPosition: const Duration(seconds: 2),
      ),
      StrokeAudioPlaybackState.upcoming,
    );
    expect(
      StrokeAudioTimeline.stateFor(
        stroke: linkedStroke,
        recording: recording,
        playbackPosition: const Duration(milliseconds: 4500),
      ),
      StrokeAudioPlaybackState.current,
    );
    expect(
      StrokeAudioTimeline.stateFor(
        stroke: linkedStroke,
        recording: recording,
        playbackPosition: const Duration(seconds: 6),
      ),
      StrokeAudioPlaybackState.reached,
    );
    expect(
      StrokeAudioTimeline.linkedStrokeCount(
        strokes: [linkedStroke, unlinkedStroke],
        recording: recording,
      ),
      1,
    );
  });
}

Stroke _stroke({required String id, required DateTime start, DateTime? end}) {
  return Stroke(
    id: id,
    tool: ToolType.pen,
    color: const Color(0xFF000000),
    width: 3,
    points: [
      StrokePoint(offset: Offset.zero, pressure: 1, time: start),
      if (end != null)
        StrokePoint(offset: const Offset(10, 10), pressure: 1, time: end),
    ],
  );
}
