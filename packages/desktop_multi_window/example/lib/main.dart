import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:desktop_lifecycle/desktop_lifecycle.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_multi_window_example/event_widget.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main(List<String> args) {
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args[2].isEmpty ? const {} : jsonDecode(args[2]) as Map<String, dynamic>;
    runApp(_ExampleSubWindow(
      windowController: WindowController.fromWindowId(windowId),
      args: argument,
    ));
  } else {
    runApp(const _ExampleMainWindow());
  }
}

class _ExampleMainWindow extends StatefulWidget {
  const _ExampleMainWindow({Key? key}) : super(key: key);

  @override
  State<_ExampleMainWindow> createState() => _ExampleMainWindowState();
}

class _ExampleMainWindowState extends State<_ExampleMainWindow> {
  final random = Random();
  final stopwatch = Stopwatch();
  int throttledFramesCount = 0;

  void throttle() {
    stopwatch.start();

    int duration = random.nextInt(50) + 10;

    while (stopwatch.elapsedMilliseconds < duration) {}
    stopwatch.reset();
    stopwatch.stop();

    if (throttledFramesCount > 7) {
      throttledFramesCount = 0;
      return;
    }

    throttledFramesCount++;

    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      throttle();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Stack(
          children: [
            Column(
              children: [
                TextButton(
                  onPressed: () async {
                    final window = await DesktopMultiWindow.createWindow(jsonEncode({
                      'args1': 'Sub window',
                      'args2': 100,
                      'args3': true,
                      'business': 'business_test',
                    }));
                    window
                      ..setFrame(const Offset(0, 0) & const Size(1280, 720))
                      ..center()
                      ..setTitle('Another window')
                      ..show();
                  },
                  child: const Text('Create a new World!'),
                ),
                TextButton(
                  onPressed: throttle,
                  child: const Text('Throttle'),
                ),
                TextButton(
                  child: const Text('Send event to all sub windows'),
                  onPressed: () async {
                    final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
                    for (final windowId in subWindowIds) {
                      DesktopMultiWindow.invokeMethod(
                        windowId,
                        'broadcast',
                        'Broadcast from main window',
                      );
                    }
                  },
                ),
                Row(
                  children: [
                    for (var i = 0; i < 8; ++i) const WobblyAvatar(),
                  ],
                ),
                Expanded(
                  child: EventWidget(controller: WindowController.fromWindowId(0)),
                )
              ],
            ),
            const Positioned(
              top: 40,
              right: 16,
              child: SizedBox(width: 200, height: 200, child: FrameTimingStatsWidget()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleSubWindow extends StatelessWidget {
  const _ExampleSubWindow({
    Key? key,
    required this.windowController,
    required this.args,
  }) : super(key: key);

  final WindowController windowController;
  final Map? args;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Stack(
          children: [
            Column(
              children: [
                if (args != null)
                  Text(
                    'Arguments: ${args.toString()}',
                    style: const TextStyle(fontSize: 20),
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: DesktopLifecycle.instance.isActive,
                  builder: (context, active, child) {
                    if (active) {
                      return const Text('Window Active');
                    } else {
                      return const Text('Window Inactive');
                    }
                  },
                ),
                TextButton(
                  onPressed: () async {
                    windowController.close();
                  },
                  child: const Text('Close this window'),
                ),
                Row(
                  children: [
                    for (var i = 0; i < 8; ++i) const WobblyAvatar(),
                  ],
                ),
                Expanded(child: EventWidget(controller: windowController)),
              ],
            ),
            const Positioned(
              top: 40,
              right: 16,
              child: SizedBox(width: 200, height: 200, child: FrameTimingStatsWidget()),
            ),
          ],
        ),
      ),
    );
  }
}

class FrameTimingStatsWidget extends StatefulWidget {
  const FrameTimingStatsWidget({super.key});

  @override
  State<FrameTimingStatsWidget> createState() => _FrameTimingStatsWidgetState();
}

class _FrameTimingStatsWidgetState extends State<FrameTimingStatsWidget> {
  final List<double> _frameTimes = [];
  double _averageFps = 0;
  double _uiFrameTime = 0;
  double _rasterFrameTime = 0;
  double _vsyncOverhead = 0;
  int _jankCount = 0;
  int _totalFrames = 0;

  @override
  void initState() {
    super.initState();
    _startTrackingFrameTiming();
  }

  void _startTrackingFrameTiming() {
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    _totalFrames += timings.length;

    for (final frame in timings) {
      final totalSpan = frame.totalSpan.inMilliseconds;
      final buildDuration = frame.buildDuration.inMilliseconds;
      final rasterDuration = frame.rasterDuration.inMilliseconds;
      final vsyncOverhead = frame.vsyncOverhead.inMilliseconds;

      _frameTimes.add(totalSpan.toDouble());
      _uiFrameTime = buildDuration.toDouble();
      _rasterFrameTime = rasterDuration.toDouble();
      _vsyncOverhead = vsyncOverhead.toDouble();

      if (totalSpan > 16) {
        _jankCount++;
      }

      if (_frameTimes.length > 20) {
        _frameTimes.removeAt(0);
      }
      _averageFps = _calculateAverageFps();
    }

    if (mounted) {
      setState(() {});
    }
  }

  double _calculateAverageFps() {
    if (_frameTimes.isEmpty) return 0;
    final averageFrameTime = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
    return 1000 / averageFrameTime;
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatRow('Average FPS', _averageFps.toStringAsFixed(1), _getFpsColor(_averageFps)),
          _buildStatRow('UI Frame Time', '${_uiFrameTime.toStringAsFixed(1)} ms', _getTimeColor(_uiFrameTime)),
          _buildStatRow(
              'Raster Frame Time', '${_rasterFrameTime.toStringAsFixed(1)} ms', _getTimeColor(_rasterFrameTime)),
          _buildStatRow('VSync Overhead', '${_vsyncOverhead.toStringAsFixed(1)} ms', _getVsyncColor(_vsyncOverhead)),
          _buildStatRow('Jank Count', '$_jankCount', _jankCount > 0 ? Colors.orange : Colors.green),
          _buildStatRow('Total Frames', '$_totalFrames', Colors.white),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Color _getFpsColor(double fps) {
    if (fps >= 58) return Colors.green;
    if (fps >= 30) return Colors.orange;
    return Colors.red;
  }

  Color _getTimeColor(double timeMs) {
    if (timeMs <= 16) return Colors.green;
    if (timeMs <= 32) return Colors.orange;
    return Colors.red;
  }

  Color _getVsyncColor(double overheadMs) {
    if (overheadMs <= 2) return Colors.green;
    if (overheadMs <= 5) return Colors.orange;
    return Colors.red;
  }
}

class WobblyAvatar extends StatefulWidget {
  const WobblyAvatar({super.key});

  @override
  State<WobblyAvatar> createState() => _WobblyAvatarState();
}

class _WobblyAvatarState extends State<WobblyAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _updateAnimation();

    _controller.addListener(() {
      if (_controller.status == AnimationStatus.completed || _controller.status == AnimationStatus.dismissed) {
        if (_random.nextDouble() < 0.1) {
          _updateAnimation();
        }
      }
    });
  }

  void _updateAnimation() {
    final newAmplitude = 0.05 + _random.nextDouble() * 0.15;
    final newDuration = 1500 + _random.nextInt(2000);

    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -newAmplitude),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -newAmplitude, end: newAmplitude),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween(begin: newAmplitude, end: 0.0),
        weight: 1,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );

    _controller.duration = Duration(milliseconds: newDuration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _animation.value,
          child: child,
          origin: const Offset(75, 50),
        );
      },
      child: SvgPicture.asset(
        "assets/avatar.svg",
        width: 150,
        height: 100,
      ),
    );
  }
}
