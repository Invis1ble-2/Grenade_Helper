// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:chewie/src/animated_play_pause.dart';
import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/material/material_progress_bar.dart';
import 'package:chewie/src/material/widgets/options_dialog.dart';
import 'package:chewie/src/material/widgets/playback_speed_dialog.dart';
import 'package:chewie/src/models/option_item.dart';
import 'package:chewie/src/models/subtitle_model.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// 项目内定制版桌面视频控件：
/// 开始播放时立即隐藏上下控制栏，避免默认延时带来的观感问题。
class InstantHideDesktopVideoControls extends StatefulWidget {
  const InstantHideDesktopVideoControls({
    this.showPlayButton = true,
    super.key,
  });

  final bool showPlayButton;

  @override
  State<StatefulWidget> createState() {
    return _InstantHideDesktopVideoControlsState();
  }
}

class _InstantHideDesktopVideoControlsState
    extends State<InstantHideDesktopVideoControls>
    with SingleTickerProviderStateMixin {
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  late var _subtitlesPosition = Duration.zero;
  bool _subtitleOn = false;
  Timer? _showAfterExpandCollapseTimer;
  bool _dragging = false;
  bool _displayTapped = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;
  bool _wasPlaying = false;

  final barHeight = 48.0 * 1.5;
  final marginSize = 5.0;

  late VideoPlayerController controller;
  ChewieController? _chewieController;
  late final FocusNode _focusNode;

  ChewieController get chewieController => _chewieController!;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.requestFocus();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _playPause();
    } else if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _seekForward();
    } else if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _seekBackward();
    } else if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (chewieController.isFullScreen) {
        _onExpandCollapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder?.call(
            context,
            chewieController.videoPlayerController.value.errorDescription!,
          ) ??
          const Center(child: Icon(Icons.error, color: Colors.white, size: 42));
    }

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyPress,
      child: MouseRegion(
        onHover: (_) {
          _focusNode.requestFocus();
          _cancelAndRestartTimer();
        },
        child: GestureDetector(
          onTap: () {
            final wasPlaying = controller.value.isPlaying;
            _playPause();
            if (wasPlaying) {
              _cancelAndRestartTimer();
            }
          },
          child: AbsorbPointer(
            absorbing: notifier.hideStuff,
            child: Stack(
              children: [
                if (_displayBufferingIndicator)
                  _chewieController?.bufferingBuilder?.call(context) ??
                      const Center(child: CircularProgressIndicator())
                else
                  _buildHitArea(),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (_subtitleOn)
                      Transform.translate(
                        offset: Offset(
                          0.0,
                          notifier.hideStuff ? barHeight * 0.8 : 0.0,
                        ),
                        child: _buildSubtitles(
                          context,
                          chewieController.subtitle!,
                        ),
                      ),
                    _buildBottomBar(context),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  Widget _buildSubtitleToggle({IconData? icon, bool isPadded = false}) {
    return IconButton(
      padding: isPadded ? const EdgeInsets.all(8.0) : EdgeInsets.zero,
      icon: Icon(icon, color: _subtitleOn ? Colors.white : Colors.grey[700]),
      onPressed: _onSubtitleTap,
    );
  }

  Widget _buildOptionsButton({IconData? icon, bool isPadded = false}) {
    final options = <OptionItem>[
      OptionItem(
        onTap: (context) async {
          Navigator.pop(context);
          _onSpeedButtonTap();
        },
        iconData: Icons.speed,
        title: chewieController.optionsTranslation?.playbackSpeedButtonText ??
            'Playback speed',
      ),
    ];

    if (chewieController.additionalOptions != null &&
        chewieController.additionalOptions!(context).isNotEmpty) {
      options.addAll(chewieController.additionalOptions!(context));
    }

    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: IconButton(
        padding: isPadded ? const EdgeInsets.all(8.0) : EdgeInsets.zero,
        onPressed: () async {
          _hideTimer?.cancel();

          if (chewieController.optionsBuilder != null) {
            await chewieController.optionsBuilder!(context, options);
          } else {
            await showModalBottomSheet<OptionItem>(
              context: context,
              isScrollControlled: true,
              useRootNavigator: chewieController.useRootNavigator,
              builder: (context) => OptionsDialog(
                options: options,
                cancelButtonText:
                    chewieController.optionsTranslation?.cancelButtonText,
              ),
            );
          }

          if (_latestValue.isPlaying) {
            _startHideTimer();
          }
        },
        icon: Icon(icon ?? Icons.more_vert, color: Colors.white),
      ),
    );
  }

  Widget _buildSubtitles(BuildContext context, Subtitles subtitles) {
    if (!_subtitleOn) {
      return const SizedBox();
    }
    final currentSubtitle = subtitles.getByPosition(_subtitlesPosition);
    if (currentSubtitle.isEmpty) {
      return const SizedBox();
    }

    if (chewieController.subtitleBuilder != null) {
      return chewieController.subtitleBuilder!(
        context,
        currentSubtitle.first!.text,
      );
    }

    return Padding(
      padding: EdgeInsets.all(marginSize),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0x96000000),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          currentSubtitle.first!.text.toString(),
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  AnimatedOpacity _buildBottomBar(BuildContext context) {
    final iconColor = Theme.of(context).textTheme.labelLarge!.color;

    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        height: barHeight + (chewieController.isFullScreen ? 20.0 : 0),
        padding: EdgeInsets.only(
          bottom: chewieController.isFullScreen ? 10.0 : 15,
        ),
        child: SafeArea(
          bottom: chewieController.isFullScreen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            verticalDirection: VerticalDirection.up,
            children: [
              Flexible(
                child: Row(
                  children: <Widget>[
                    _buildPlayPause(controller),
                    if (chewieController.allowMuting)
                      _buildMuteButton(controller),
                    if (chewieController.isLive)
                      const Expanded(child: Text('LIVE'))
                    else
                      _buildPosition(iconColor),
                    const Spacer(),
                    if (chewieController.showControls &&
                        chewieController.subtitle != null &&
                        chewieController.subtitle!.isNotEmpty)
                      _buildSubtitleToggle(icon: Icons.subtitles),
                    if (chewieController.showOptions)
                      _buildOptionsButton(icon: Icons.settings),
                    if (chewieController.allowFullScreen) _buildExpandButton(),
                  ],
                ),
              ),
              if (!chewieController.isLive)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.only(
                      right: 20,
                      left: 20,
                      bottom: chewieController.isFullScreen ? 5.0 : 0,
                    ),
                    child: Row(children: [_buildProgressBar()]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  GestureDetector _buildExpandButton() {
    return GestureDetector(
      onTap: _onExpandCollapse,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (chewieController.isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 12.0),
          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
          child: Center(
            child: Icon(
              chewieController.isFullScreen
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished = _latestValue.position >= _latestValue.duration &&
        _latestValue.duration.inSeconds > 0;
    final bool showPlayButton =
        widget.showPlayButton && !_dragging && !notifier.hideStuff;

    return GestureDetector(
      onTap: () {
        if (_latestValue.isPlaying) {
          if (_chewieController?.pauseOnBackgroundTap ?? false) {
            _playPause();
            _cancelAndRestartTimer();
          } else {
            if (_displayTapped) {
              setState(() {
                notifier.hideStuff = true;
              });
            } else {
              _cancelAndRestartTimer();
            }
          }
        } else {
          _playPause();

          setState(() {
            notifier.hideStuff = true;
          });
        }
      },
      child: CenterPlayButton(
        backgroundColor: Colors.black54,
        iconColor: Colors.white,
        isFinished: isFinished,
        isPlaying: controller.value.isPlaying,
        show: showPlayButton,
        onPressed: _playPause,
      ),
    );
  }

  Future<void> _onSpeedButtonTap() async {
    _hideTimer?.cancel();

    final chosenSpeed = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: chewieController.useRootNavigator,
      builder: (context) => PlaybackSpeedDialog(
        speeds: chewieController.playbackSpeeds,
        selected: _latestValue.playbackSpeed,
      ),
    );

    if (chosenSpeed != null) {
      controller.setPlaybackSpeed(chosenSpeed);
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

  GestureDetector _buildMuteButton(VideoPlayerController controller) {
    return GestureDetector(
      onTap: () {
        _cancelAndRestartTimer();

        if (_latestValue.volume == 0) {
          controller.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller.value.volume;
          controller.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRect(
          child: Container(
            height: barHeight,
            padding: const EdgeInsets.only(right: 15.0),
            child: Icon(
              _latestValue.volume > 0 ? Icons.volume_up : Icons.volume_off,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildPlayPause(VideoPlayerController controller) {
    return GestureDetector(
      onTap: _playPause,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        margin: const EdgeInsets.only(left: 8.0, right: 4.0),
        padding: const EdgeInsets.only(left: 12.0, right: 12.0),
        child: AnimatedPlayPause(
          playing: controller.value.isPlaying,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPosition(Color? iconColor) {
    final position = _latestValue.position;
    final duration = _latestValue.duration;

    return Text(
      '${formatDuration(position)} / ${formatDuration(duration)}',
      style: const TextStyle(fontSize: 14.0, color: Colors.white),
    );
  }

  void _onSubtitleTap() {
    setState(() {
      _subtitleOn = !_subtitleOn;
    });
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    _subtitleOn = chewieController.showSubtitles &&
        (chewieController.subtitle?.isNotEmpty ?? false);
    _wasPlaying = controller.value.isPlaying;
    controller.addListener(_updateState);

    _updateState();

    if (controller.value.isPlaying || chewieController.autoPlay) {
      notifier.hideStuff = true;
      _hideTimer?.cancel();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted || controller.value.isPlaying) return;
        setState(() {
          notifier.hideStuff = false;
        });
      });
    }
  }

  void _onExpandCollapse() {
    setState(() {
      notifier.hideStuff = true;
    });

    chewieController.toggleFullScreen();

    _showAfterExpandCollapseTimer = Timer(
      const Duration(milliseconds: 300),
      () {
        setState(() {
          _cancelAndRestartTimer();
        });
      },
    );
  }

  void _playPause() {
    if (controller.value.isPlaying) {
      setState(() {
        notifier.hideStuff = false;
      });

      _hideTimer?.cancel();
      controller.pause();
    } else {
      _hideTimer?.cancel();
      setState(() {
        notifier.hideStuff = true;
        _displayTapped = false;
      });

      if (!controller.value.isInitialized) {
        controller.initialize().then((_) {
          if (!mounted) return;
          controller.play();
        });
      } else {
        controller.play();
      }
    }
  }

  void _startHideTimer() {
    final hideControlsTimer = chewieController.hideControlsTimer.isNegative
        ? ChewieController.defaultHideControlsTimer
        : chewieController.hideControlsTimer;
    _hideTimer = Timer(hideControlsTimer, () {
      setState(() {
        notifier.hideStuff = true;
      });
    });
  }

  void _bufferingTimerTimeout() {
    _displayBufferingIndicator = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _updateState() {
    if (!mounted) return;

    final bool buffering = getIsBuffering(controller);
    final bool isPlaying = controller.value.isPlaying;
    final bool startedPlaying = !_wasPlaying && isPlaying;

    if (chewieController.progressIndicatorDelay != null) {
      if (buffering) {
        _bufferingDisplayTimer ??= Timer(
          chewieController.progressIndicatorDelay!,
          _bufferingTimerTimeout,
        );
      } else {
        _bufferingDisplayTimer?.cancel();
        _bufferingDisplayTimer = null;
        _displayBufferingIndicator = false;
      }
    } else {
      _displayBufferingIndicator = buffering;
    }

    _wasPlaying = isPlaying;

    setState(() {
      _latestValue = controller.value;
      _subtitlesPosition = controller.value.position;
      if (startedPlaying) {
        notifier.hideStuff = true;
      }
    });
  }

  void _seekBackward() {
    _seekRelative(const Duration(seconds: -10));
  }

  void _seekForward() {
    _seekRelative(const Duration(seconds: 10));
  }

  void _seekRelative(Duration relativeSeek) {
    _cancelAndRestartTimer();
    final position = _latestValue.position + relativeSeek;
    final duration = _latestValue.duration;

    if (position < Duration.zero) {
      controller.seekTo(Duration.zero);
    } else if (position > duration) {
      controller.seekTo(duration);
    } else {
      controller.seekTo(position);
    }
  }

  Widget _buildProgressBar() {
    return Expanded(
      child: MaterialVideoProgressBar(
        controller,
        onDragStart: () {
          setState(() {
            _dragging = true;
          });

          _hideTimer?.cancel();
        },
        onDragUpdate: () {
          _hideTimer?.cancel();
        },
        onDragEnd: () {
          setState(() {
            _dragging = false;
          });

          _startHideTimer();
        },
        colors: chewieController.materialProgressColors ??
            ChewieProgressColors(
              playedColor: Theme.of(context).colorScheme.secondary,
              handleColor: Theme.of(context).colorScheme.secondary,
              bufferedColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.5),
              backgroundColor: Theme.of(
                context,
              ).disabledColor.withValues(alpha: 0.5),
            ),
        draggableProgressBar: chewieController.draggableProgressBar,
      ),
    );
  }
}
