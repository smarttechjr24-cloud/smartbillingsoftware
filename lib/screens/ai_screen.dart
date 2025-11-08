import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class VoiceAssistantChatbotScreen extends StatefulWidget {
  const VoiceAssistantChatbotScreen({super.key});

  @override
  State<VoiceAssistantChatbotScreen> createState() =>
      _VoiceAssistantChatbotScreenState();
}

class _VoiceAssistantChatbotScreenState
    extends State<VoiceAssistantChatbotScreen> {
  final String _baseUrl = "http://127.0.0.1:8000/ai/chatbot/";

  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  // Workflow state
  String?
  _currentAction; // "add_customer", "add_product", "create_invoice", "create_quotation"
  int _stepIndex = 0;
  Map<String, dynamic> _collectedData = {};
  List<Map<String, dynamic>> _items = []; // for invoice/quotation

  // Steps for each action
  final Map<String, List<Map<String, dynamic>>> _workflows = {
    "add_customer": [
      {
        "field": "customer_name",
        "prompt": "What is the customer name?",
        "required": true,
      },
      {
        "field": "mobile",
        "prompt": "What is the mobile number?",
        "required": true,
      },
      {"field": "address", "prompt": "What is the address?", "required": true},
      {
        "field": "gst_number",
        "prompt": "GST number? Say skip if not applicable.",
        "required": false,
      },
    ],
    "add_product": [
      {
        "field": "product_name",
        "prompt": "What is the product name?",
        "required": true,
      },
      {
        "field": "rate",
        "prompt": "What is the price per unit?",
        "required": true,
        "type": "number",
      },
      {
        "field": "unit",
        "prompt": "What is the unit? For example, piece, kilogram, or unit.",
        "required": true,
      },
    ],
    "create_invoice": [
      {
        "field": "customer_name",
        "prompt": "Customer name for this invoice?",
        "required": true,
      },
      {
        "field": "mobile",
        "prompt": "Customer mobile number?",
        "required": true,
      },
      {
        "field": "billing_address",
        "prompt": "Billing address?",
        "required": true,
      },
      {
        "field": "shipping_address",
        "prompt": "Shipping address?",
        "required": true,
      },
      {
        "field": "gst_percentage",
        "prompt": "GST percentage? For example, 5, 12, or 18.",
        "required": true,
        "type": "number",
      },
      {
        "field": "due_in_days",
        "prompt": "Payment due in how many days?",
        "required": true,
        "type": "number",
      },
      {
        "field": "items",
        "prompt":
            "Let's add items. Say the item name, quantity, rate, and unit. Say done when finished.",
        "required": true,
        "type": "items",
      },
      {
        "field": "note",
        "prompt": "Any note or comment? Say skip if none.",
        "required": false,
      },
    ],
    "create_quotation": [
      {
        "field": "customer_name",
        "prompt": "Customer name for this quotation?",
        "required": true,
      },
      {
        "field": "mobile",
        "prompt": "Customer mobile number?",
        "required": true,
      },
      {
        "field": "billing_address",
        "prompt": "Billing address?",
        "required": true,
      },
      {
        "field": "shipping_address",
        "prompt": "Shipping address?",
        "required": true,
      },
      {
        "field": "gst_percentage",
        "prompt": "GST percentage?",
        "required": true,
        "type": "number",
      },
      {
        "field": "items",
        "prompt":
            "Let's add items. Say the item name, quantity, rate, and unit. Say done when finished.",
        "required": true,
        "type": "items",
      },
      {
        "field": "note",
        "prompt": "Any note? Say skip if none.",
        "required": false,
      },
    ],
  };

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    _speechAvailable = await _speech.initialize();
    setState(() {});
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
  }

  Future<void> _speak(String text) async {
    setState(() => _isSpeaking = true);
    await _tts.speak(text);
  }

  Future<void> _listen() async {
    if (!_speechAvailable || _isListening) return;
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _processVoiceInput(result.recognizedWords);
        }
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  void _startAction(String action) {
    setState(() {
      _currentAction = action;
      _stepIndex = 0;
      _collectedData = {};
      _items = [];
    });
    _askNextQuestion();
  }

  void _askNextQuestion() {
    if (_currentAction == null) return;
    final steps = _workflows[_currentAction]!;
    if (_stepIndex >= steps.length) {
      _showPreview();
      return;
    }
    final step = steps[_stepIndex];
    _speak(step["prompt"]);
    Future.delayed(const Duration(milliseconds: 1500), () {
      _listen();
    });
  }

  void _processVoiceInput(String input) {
    _stopListening();
    if (_currentAction == null) return;

    final steps = _workflows[_currentAction]!;
    final step = steps[_stepIndex];
    final field = step["field"] as String;
    final type = step["type"] as String?;
    final required = step["required"] as bool;

    // Handle skip for optional fields
    if (!required &&
        (input.toLowerCase().contains("skip") ||
            input.toLowerCase().contains("none"))) {
      _collectedData[field] = "";
      _stepIndex++;
      _askNextQuestion();
      return;
    }

    // Handle items collection
    if (type == "items") {
      if (input.toLowerCase().contains("done")) {
        if (_items.isEmpty) {
          _speak("You must add at least one item. Let's try again.");
          _listen();
          return;
        }
        _collectedData["items"] = _items;
        _stepIndex++;
        _askNextQuestion();
        return;
      }
      // Parse item: "widget A 2 pieces at 120"
      final parsed = _parseItem(input);
      if (parsed != null) {
        _items.add(parsed);
        _speak("Item added. Say another item or say done.");
        _listen();
      } else {
        _speak(
          "I couldn't parse that. Please say item name, quantity, unit, and rate. For example, widget A, 2 pieces at 120.",
        );
        _listen();
      }
      return;
    }

    // Handle number fields
    if (type == "number") {
      final num = double.tryParse(input.replaceAll(RegExp(r'[^\d.]'), ''));
      if (num == null || num <= 0) {
        _speak("Please provide a valid positive number.");
        _listen();
        return;
      }
      _collectedData[field] = num;
    } else {
      _collectedData[field] = input.trim();
    }

    _stepIndex++;
    _askNextQuestion();
  }

  Map<String, dynamic>? _parseItem(String input) {
    // Simple regex: "name qty unit at rate"
    final match = RegExp(
      r'(.+?)\s+(\d+\.?\d*)\s+([\w]+)\s+at\s+(\d+\.?\d*)',
      caseSensitive: false,
    ).firstMatch(input.toLowerCase());
    if (match != null) {
      return {
        "item": match.group(1)?.trim() ?? "",
        "qty": double.tryParse(match.group(2) ?? "0") ?? 0,
        "unit": match.group(3)?.trim() ?? "Unit",
        "rate": double.tryParse(match.group(4) ?? "0") ?? 0,
      };
    }
    return null;
  }

  void _showPreview() {
    _speak("All information collected. Please review and confirm.");
    setState(() {}); // Trigger rebuild to show preview
  }

  Future<void> _confirmAndSave() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _speak("You are not signed in.");
      return;
    }

    String message = "";
    String intent = "";

    switch (_currentAction) {
      case "add_customer":
        intent = "add_customer";
        message =
            "Add customer ${_collectedData['customer_name']} phone ${_collectedData['mobile']} address ${_collectedData['address']}";
        if (_collectedData['gst_number']?.toString().isNotEmpty == true) {
          message += " GST ${_collectedData['gst_number']}";
        }
        break;
      case "add_product":
        intent = "add_product";
        message =
            "Add product ${_collectedData['product_name']} at ${_collectedData['rate']} per ${_collectedData['unit']}";
        break;
      case "create_invoice":
        intent = "get_invoice_create";
        message = _buildInvoiceMessage();
        break;
      case "create_quotation":
        intent = "get_quotation_create";
        message = _buildQuotationMessage();
        break;
    }

    try {
      final res = await http.post(
        Uri.parse(_baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"uid": uid, "message": message}),
      );
      final data = jsonDecode(res.body);
      final reply = data["response"] ?? data["error"] ?? "No response";
      _speak(reply);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reply)));
      _resetWorkflow();
    } catch (e) {
      _speak("Error saving data: $e");
    }
  }

  String _buildInvoiceMessage() {
    final items = (_collectedData["items"] as List<Map<String, dynamic>>)
        .map(
          (it) => "${it['qty']} ${it['unit']} ${it['item']} at ${it['rate']}",
        )
        .join(", ");
    return "Create invoice for ${_collectedData['customer_name']} mobile ${_collectedData['mobile']} "
        "billing ${_collectedData['billing_address']} shipping ${_collectedData['shipping_address']} "
        "with $items GST ${_collectedData['gst_percentage']}% due in ${_collectedData['due_in_days']} days. "
        "Note: ${_collectedData['note'] ?? 'None'}";
  }

  String _buildQuotationMessage() {
    final items = (_collectedData["items"] as List<Map<String, dynamic>>)
        .map(
          (it) => "${it['qty']} ${it['unit']} ${it['item']} at ${it['rate']}",
        )
        .join(", ");
    return "Create quotation for ${_collectedData['customer_name']} mobile ${_collectedData['mobile']} "
        "billing ${_collectedData['billing_address']} shipping ${_collectedData['shipping_address']} "
        "with $items GST ${_collectedData['gst_percentage']}%. Note: ${_collectedData['note'] ?? 'None'}";
  }

  void _resetWorkflow() {
    setState(() {
      _currentAction = null;
      _stepIndex = 0;
      _collectedData = {};
      _items = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Voice AI Assistant"),
        backgroundColor: Colors.teal.shade700,
      ),
      body: _currentAction == null
          ? _buildActionGrid()
          : (_stepIndex >= _workflows[_currentAction]!.length
                ? _buildPreview()
                : _buildListeningUI()),
    );
  }

  Widget _buildActionGrid() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "What would you like to do?",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildActionCard(
                  "Add Customer",
                  Icons.person_add,
                  Colors.blue,
                  () => _startAction("add_customer"),
                ),
                _buildActionCard(
                  "Add Product",
                  Icons.inventory_2,
                  Colors.orange,
                  () => _startAction("add_product"),
                ),
                _buildActionCard(
                  "Create Invoice",
                  Icons.receipt_long,
                  Colors.green,
                  () => _startAction("create_invoice"),
                ),
                _buildActionCard(
                  "Create Quotation",
                  Icons.request_quote,
                  Colors.purple,
                  () => _startAction("create_quotation"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.yellow, Colors.orange],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListeningUI() {
    final step = _workflows[_currentAction]![_stepIndex];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isListening ? Icons.mic : Icons.mic_off,
            size: 80,
            color: _isListening ? Colors.red : Colors.grey,
          ),
          const SizedBox(height: 20),
          Text(
            _isListening ? "Listening..." : "Preparing...",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              step["prompt"],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 30),
          if (_isListening)
            ElevatedButton.icon(
              onPressed: _stopListening,
              icon: const Icon(Icons.stop),
              label: const Text("Stop"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Review Your Data",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _collectedData.entries.map((e) {
                  if (e.key == "items") {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Items:",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ...(e.value as List<Map<String, dynamic>>).map((it) {
                          return Text(
                            "  • ${it['item']} - ${it['qty']} ${it['unit']} @ ₹${it['rate']}",
                          );
                        }).toList(),
                      ],
                    );
                  }
                  return Text("${e.key}: ${e.value}");
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _resetWorkflow,
                  icon: const Icon(Icons.edit),
                  label: const Text("Edit"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _confirmAndSave,
                  icon: const Icon(Icons.check),
                  label: const Text("Confirm"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}
