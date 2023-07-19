import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chromatic scale',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Chromatic scale'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

const int _kRIFF = 0x52494646; // "RIFF"
const int _kWAVE = 0x57415645; // "WAVE"
const int _kfmt_ = 0x666d7420; // "fmt "
const int _kdata = 0x64617461; // "data"
const int _kMaxSize = 0x7fffffff;
const int _kWavHeaderSize = 44;

// Generate a WAV header for a much-too-long file, as length may be unknown ahead of time, or infinite
int _writeWavHeader(ByteData dst, int hz, int nChannels, int nBytes) {
  dst.setUint32(0, _kRIFF, Endian.big);
  dst.setUint32(4, _kMaxSize, Endian.little);
  dst.setUint32(8, _kWAVE, Endian.big);
  dst.setUint32(12, _kfmt_, Endian.big);
  dst.setUint32(16, 16, Endian.little);
  dst.setUint16(20, 1, Endian.little);
  dst.setUint16(22, nChannels, Endian.little);
  dst.setUint32(24, hz, Endian.little);
  dst.setUint32(28, hz * nChannels * nBytes, Endian.little);
  dst.setUint16(32, nBytes * nChannels, Endian.little);
  dst.setUint16(34, nBytes * 8, Endian.little);
  dst.setUint32(36, _kdata, Endian.big);
  dst.setUint32(40, _kMaxSize, Endian.little);
  return _kWavHeaderSize;
}

// Audio source that generates PCM data and returns it with a WAV header
class StreamingSource extends StreamAudioSource {
  static const int _sampleRate = 44100;
  double frequency;

  StreamingSource([this.frequency = 440]);

  List<int> generate(int start, int end) {
    bool hasHeader = start == 0;
    int len = end - start + (hasHeader ? _kWavHeaderSize : 0);
    Uint8List data = Uint8List(len);
    int endOfHeader = start == 0 ? _writeWavHeader(data.buffer.asByteData(), _sampleRate, 1, 1) : 0;
    for (int i = 0; i < data.length - endOfHeader; i++) {
      double samp = sin(i * 2 * pi * frequency / _sampleRate) * 0.5 + 0.5;
      data[endOfHeader + i] = (samp * 255).toInt();
    }
    print('Generating data of length $len');
    return data;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // I expect that this should be called when the player starts, and because it supports range requests,
    // gives null for the source length, and has a wave header with a longer length than the response,
    // it should receive subsequent range requests for the rest of the sound,
    // but in reality in receives only the initial request.
    int t0 = start ?? 0;
    int nSecs = 1;
    int t1 = end ?? (_sampleRate * nSecs + _kWavHeaderSize);
    print('Request for $start to $end');
    return StreamAudioResponse(
      sourceLength: null,
      contentLength: null,
      offset: null,
      stream: Stream.fromIterable([generate(t0, t1)]),
      contentType: 'audio/wav',
      rangeRequestsSupported: true,
      );
  }

}

class _MyHomePageState extends State<MyHomePage> {
  late AudioPlayer _player;
  late StreamingSource _source;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _source = StreamingSource(440);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.pause();
    await _player.setAudioSource(_source, preload: false);
  }

  Future<void> _playTone() async {
    // I expect that once this is called once, the tone will continue to play,
    // but increase in frequency almost immediately upon subsequent calls.
    _source.frequency *= pow(2.0, 1.0/12);

    // Ended up needing these two lines just to get the tone to play again on the 2nd press.
    await _player.stop();
    await _player.seek(Duration.zero);

    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _playTone,
        tooltip: 'Play',
        child: const Icon(Icons.add),
      ),
    );
  }
}
