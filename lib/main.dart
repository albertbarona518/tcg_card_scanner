import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera detection error: $e');
  }
  runApp(const TcgScannerApp());
}

class CardItem {
  final String id;
  final String name;
  final String set;
  final double value;

  CardItem({
    required this.id,
    required this.name,
    required this.set,
    required this.value,
  });
}

class TcgScannerApp extends StatelessWidget {
  const TcgScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCG Vault & Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // Shared state: List of saved cards in Vault
  final List<CardItem> _portfolioCards = [
    CardItem(id: '1', name: 'Charizard ex #223', set: 'Obsidian Flames', value: 184.50),
    CardItem(id: '2', name: 'Pikachu ex #057', set: 'Surging Sparks', value: 32.10),
    CardItem(id: '3', name: 'Gengar VMAX #271', set: 'Fusion Strike', value: 310.00),
  ];

  void _addCardsToPortfolio(List<CardItem> newCards) {
    setState(() {
      _portfolioCards.addAll(newCards);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DynamicCardScannerScreen(onAddCards: _addCardsToPortfolio),
      PortfolioVaultScreen(savedCards: _portfolioCards),
      const DeckBuilderScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Colors.black,
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scanner',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Portfolio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: 'AI Deck Builder',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TAB 1: DYNAMIC SCANNER SCREEN
// ---------------------------------------------------------------------------
class ScannedCard {
  final Rect boundingBox;
  final String name;
  final double value;

  ScannedCard({
    required this.boundingBox,
    required this.name,
    required this.value,
  });
}

class DynamicCardScannerScreen extends StatefulWidget {
  final Function(List<CardItem>) onAddCards;

  const DynamicCardScannerScreen({super.key, required this.onAddCards});

  @override
  State<DynamicCardScannerScreen> createState() => _DynamicCardScannerScreenState();
}

class _DynamicCardScannerScreenState extends State<DynamicCardScannerScreen> {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isProcessingFrame = false;

  late ObjectDetector _objectDetector;
  final TextRecognizer _textRecognizer = TextRecognizer();

  List<ScannedCard> _detectedCards = [];

  @override
  void initState() {
    super.initState();
    _initMLKit();
    _setupCamera();
  }

  void _initMLKit() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      multipleObjects: true,
      classifyObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<void> _setupCamera() async {
    if (cameras.isEmpty) {
      try {
        cameras = await availableCameras();
      } catch (e) {
        debugPrint('Error getting cameras: $e');
      }
    }

    if (cameras.isNotEmpty) {
      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      try {
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraReady = true;
          });
          _cameraController!.startImageStream(_processCameraFrame);
        }
      } catch (e) {
        debugPrint("Camera init failed: $e");
      }
    }
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage != null) {
        final objects = await _objectDetector.processImage(inputImage);
        
        if (mounted) {
          setState(() {
            _detectedCards = objects.map((obj) {
              return ScannedCard(
                boundingBox: obj.boundingBox,
                name: "Detected TCG Card",
                value: 15.00,
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Error processing frame: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  double get _totalValue =>
      _detectedCards.fold(0.0, (sum, item) => sum + item.value);

  @override
  void dispose() {
    _cameraController?.dispose();
    _objectDetector.close();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            _isCameraReady && _cameraController != null
                ? SizedBox.expand(
                    child: CameraPreview(_cameraController!),
                  )
                : Container(
                    color: Colors.grey[950],
                    child: const Center(
                      child: Text(
                        "Initializing Camera & ML Kit...",
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    ),
                  ),

            Positioned.fill(
              child: CustomPaint(
                painter: DynamicCardPainter(cards: _detectedCards),
              ),
            ),

            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.6), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _detectedCards.isEmpty
                              ? "Scanning for cards..."
                              : "Detected: ${_detectedCards.length} ${_detectedCards.length == 1 ? 'Card' : 'Cards'}",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Estimated Value: \$${_totalValue.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _detectedCards.isEmpty
                          ? null
                          : () {
                              final newItems = _detectedCards.map((c) {
                                return CardItem(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  name: c.name,
                                  set: 'Scanned Card Set',
                                  value: c.value,
                                );
                              }).toList();

                              widget.onAddCards(newItems);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Saved ${newItems.length} card(s) to Portfolio Vault!',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.add_to_photos, size: 20),
                      label: Text(
                        _detectedCards.length > 1 ? 'Add All' : 'Add Card',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class DynamicCardPainter extends CustomPainter {
  final List<ScannedCard> cards;

  DynamicCardPainter({required this.cards});

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (var card in cards) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(card.boundingBox, const Radius.circular(8)),
        boxPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DynamicCardPainter oldDelegate) {
    return oldDelegate.cards != cards;
  }
}

// ---------------------------------------------------------------------------
// TAB 2: PORTFOLIO / VAULT SCREEN
// ---------------------------------------------------------------------------
class PortfolioVaultScreen extends StatelessWidget {
  final List<CardItem> savedCards;

  const PortfolioVaultScreen({super.key, required this.savedCards});

  double get totalPortfolioValue =>
      savedCards.fold(0.0, (sum, card) => sum + card.value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Vault & Portfolio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () {},
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Portfolio Value', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 6),
                      Text(
                        '\$${totalPortfolioValue.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Icon(Icons.trending_up, color: Colors.greenAccent, size: 36),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saved Cards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${savedCards.length} Items', style: const TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: savedCards.isEmpty
                  ? const Center(
                      child: Text('No cards saved yet. Scan cards using the Scanner tab!'),
                    )
                  : ListView.builder(
                      itemCount: savedCards.length,
                      itemBuilder: (context, index) {
                        final card = savedCards[index];
                        return Card(
                          color: Colors.grey[900],
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const Icon(Icons.style, color: Colors.greenAccent),
                            title: Text(card.name),
                            subtitle: Text(card.set),
                            trailing: Text(
                              '\$${card.value.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TAB 3: AI DECK BUILDER / CHASE FINDER
// ---------------------------------------------------------------------------
class DeckBuilderScreen extends StatelessWidget {
  const DeckBuilderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Deck Builder & Chase Finder'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 64, color: Colors.greenAccent),
              SizedBox(height: 16),
              Text(
                'AI Deck Optimization',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Scan cards into your Vault to receive automated synergy analysis and deck recommendations.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}