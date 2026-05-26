import 'package:flutter/material.dart';
import 'package:any_image_view/any_image_view.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Any Image View',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const GalleryScreen(),
    );
  }
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  XFile? _picked;

  Future<void> _pick() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image != null) setState(() => _picked = image);
    } catch (e) {
      debugPrint('pick error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Any Image View'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _pick,
            tooltip: 'Pick from gallery',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_picked != null)
            _Section(
              title: 'Picked image (XFile)',
              child: AnyImageView(
                imagePath: _picked,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          _Section(
            title: 'Network image — tap for fullscreen',
            child: AnyImageView(
              imagePath:
                  'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              enableFullscreen: true,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          _Section(
            title: 'PNG asset',
            child: AnyImageView(
              imagePath: 'assets/png/flutter_banner.png',
              height: 150,
              width: double.infinity,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          _Section(
            title: 'SVG asset',
            child: AnyImageView(
              imagePath: 'assets/svg/flutter.svg',
              height: 100,
              width: 100,
              fit: BoxFit.contain,
            ),
          ),
          _Section(
            title: 'Network SVG with color filter',
            child: AnyImageView(
              imagePath: 'https://www.svgrepo.com/show/530641/telephone.svg',
              height: 100,
              width: 100,
              fit: BoxFit.contain,
              svgColor: Colors.indigo,
            ),
          ),
          _Section(
            title: 'AVIF asset',
            child: AnyImageView(
              imagePath: 'assets/avif/boat.avif',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          _Section(
            title: 'AVIF — animated, network',
            child: AnyImageView(
              imagePath:
                  'https://colinbendell.github.io/webperf/animated-gif-decode/5frames.avif',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          _Section(
            title: 'Lottie animation',
            child: AnyImageView(
              imagePath: 'assets/lottie/flutter_mobile.json',
              height: 150,
              width: 150,
              fit: BoxFit.contain,
            ),
          ),
          _Section(
            title: 'Circular avatar',
            child: Center(
              child: AnyImageView(
                imagePath:
                    'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200',
                height: 120,
                width: 120,
                fit: BoxFit.cover,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.indigo, width: 3),
              ),
            ),
          ),
          _Section(
            title: 'Custom error widget',
            child: AnyImageView(
              imagePath: 'https://invalid-url.com/image.jpg',
              height: 150,
              width: double.infinity,
              borderRadius: BorderRadius.circular(12),
              errorWidget: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text('Image not available')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
