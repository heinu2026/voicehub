import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class VoiceButton extends StatefulWidget {
  final bool isListening;
  final double voiceLevel;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  
  const VoiceButton({
    super.key,
    required this.isListening,
    this.voiceLevel = 0,
    required this.onPressed,
    this.onLongPress,
  });
  
  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }
  
  @override
  void didUpdateWidget(VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isListening && !oldWidget.isListening) {
      _animationController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _animationController.stop();
      _animationController.reset();
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          final scale = widget.isListening
              ? _scaleAnimation.value
              : 1.0;
          
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isListening
                    ? AppTheme.errorColor
                    : AppTheme.primaryColor,
                boxShadow: [
                  BoxShadow(
                    color: (widget.isListening
                        ? AppTheme.errorColor
                        : AppTheme.primaryColor).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: widget.isListening ? 10 : 5,
                  ),
                ],
              ),
              child: Icon(
                widget.isListening ? Icons.mic : Icons.mic_none,
                color: Colors.white,
                size: 36,
              ),
            ),
          );
        },
      ),
    );
  }
}
