import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/activity_log_service.dart';
import '../../core/services/file_saver.dart';
import '../../core/services/loading_memo_pdf_service.dart';
import '../../core/theme/app_colors.dart';
import 'loading_memo_history_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Loading Memo Screen — form that generates a PDF matching the sample memo
// ─────────────────────────────────────────────────────────────────────────────
class LoadingMemoScreen extends StatefulWidget {
  const LoadingMemoScreen({super.key});

  @override
  State<LoadingMemoScreen> createState() => _LoadingMemoScreenState();
}

class _LoadingMemoScreenState extends State<LoadingMemoScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _vehicleController = TextEditingController();
  final _quantityController = TextEditingController();
  final _remarksController = TextEditingController();

  // Form state
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _materials = [];
  String? _selectedMaterialId;
  String? _selectedMaterialName;
  String _selectedUnit = 'Bags';
  bool _loadingMaterials = true;
  bool _generating = false;

  // Animation
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadMaterials();
  }

  @override
  void dispose() {
    _vehicleController.dispose();
    _quantityController.dispose();
    _remarksController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadMaterials() async {
    try {
      final data = await Supabase.instance.client
          .from('materials')
          .select('id, name, unit')
          .order('name');
      setState(() {
        _materials = List<Map<String, dynamic>>.from(data);
        _loadingMaterials = false;
      });
    } catch (e) {
      debugPrint('[LoadingMemo] Error loading materials: $e');
      setState(() => _loadingMaterials = false);
    }
  }

  // ── Date picker ─────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.roseGold,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ── Generate ────────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMaterialId == null) {
      _showError('Please select a material.');
      return;
    }

    setState(() => _generating = true);

    try {
      final quantity = double.parse(_quantityController.text.trim());
      final vehicleNumber = _vehicleController.text.trim().toUpperCase();
      final remarks = _remarksController.text.trim();

      // 1. Generate PDF bytes
      final pdfBytes = await LoadingMemoPdfService.generate(
        date: _selectedDate,
        vehicleNumber: vehicleNumber,
        materialName: _selectedMaterialName ?? '',
        quantity: quantity,
        unit: _selectedUnit,
        remarks: remarks.isEmpty ? null : remarks,
      );

      // 2. Persist to Supabase
      final user = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('loading_memos').insert({
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'vehicle_number': vehicleNumber,
        'material_id': _selectedMaterialId,
        'material_name': _selectedMaterialName,
        'quantity': quantity,
        'unit': _selectedUnit,
        'remarks': remarks.isEmpty ? null : remarks,
        'generated_by': user?.email ?? 'unknown',
      });

      // 3. Activity log
      await activityLog.log(
        action: 'Loading Memo Generated',
        module: 'Loading Memo',
        description:
            'Memo for $vehicleNumber — $_selectedMaterialName × $quantity $_selectedUnit',
      );

      if (!mounted) return;

      // 4. Show PDF options (Preview / Download / Share)
      final filename =
          'LoadingMemo_${vehicleNumber}_${DateFormat('ddMMMyyyy').format(_selectedDate)}.pdf';
      await FileSaver.showPdfOptions(
        context,
        filename: filename,
        bytes: pdfBytes,
      );
    } catch (e) {
      debugPrint('[LoadingMemo] Generate error: $e');
      if (mounted) _showError('Failed to generate memo: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Loading Memo'),
        actions: [
          // History button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Memo History',
              icon: const Icon(Icons.history, color: AppColors.roseGold),
              onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                    builder: (_) => const LoadingMemoHistoryScreen()),
              ),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              // ── Preview card ───────────────────────────────────────────────
              _PreviewCard(
                date: _selectedDate,
                vehicleNumber: _vehicleController.text,
                materialName: _selectedMaterialName,
                quantity: _quantityController.text,
                unit: _selectedUnit,
              ),
              const SizedBox(height: 24),

              // ── Section label ──────────────────────────────────────────────
              _sectionLabel('Dispatch Details'),
              const SizedBox(height: 14),

              // ── Date field ─────────────────────────────────────────────────
              _buildDateField(),
              const SizedBox(height: 16),

              // ── Vehicle number ─────────────────────────────────────────────
              TextFormField(
                controller: _vehicleController,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Vehicle Number',
                  hintText: 'e.g. TN69AJ1733',
                  prefixIcon:
                      Icon(Icons.local_shipping_outlined, color: AppColors.roseGold),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter vehicle number' : null,
              ),
              const SizedBox(height: 16),

              // ── Material dropdown ──────────────────────────────────────────
              _buildMaterialDropdown(),
              const SizedBox(height: 16),

              // ── Quantity + Unit row ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _quantityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        prefixIcon: Icon(Icons.numbers, color: AppColors.roseGold),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter quantity';
                        }
                        if (double.tryParse(v.trim()) == null ||
                            double.parse(v.trim()) <= 0) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildUnitChip(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Remarks ────────────────────────────────────────────────────
              TextFormField(
                controller: _remarksController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Remarks (Optional)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined, color: AppColors.roseGold),
                ),
              ),
              const SizedBox(height: 32),

              // ── Generate button ────────────────────────────────────────────
              _buildGenerateButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────────

  Widget _buildDateField() {
    return GestureDetector(
      onTap: _pickDate,
      child: AbsorbPointer(
        child: TextFormField(
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Date',
            hintText: DateFormat('dd/MM/yyyy').format(_selectedDate),
            prefixIcon:
                const Icon(Icons.calendar_today_outlined, color: AppColors.roseGold),
            suffixIcon: const Icon(Icons.arrow_drop_down, color: AppColors.roseGold),
          ),
          controller: TextEditingController(
            text: DateFormat('dd/MM/yyyy').format(_selectedDate),
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialDropdown() {
    if (_loadingMaterials) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF12141C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.roseGold.withValues(alpha: 0.15)),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.roseGold,
            ),
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedMaterialId,
      isExpanded: true,
      dropdownColor: AppColors.card,
      decoration: const InputDecoration(
        labelText: 'Material Name',
        prefixIcon: Icon(Icons.inventory_2_outlined, color: AppColors.roseGold),
      ),
      items: _materials.map((m) {
        return DropdownMenuItem<String>(
          value: m['id'].toString(),
          child: Text(
            m['name'] as String? ?? '',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (id) {
        if (id == null) return;
        final mat = _materials.firstWhere((m) => m['id'].toString() == id);
        setState(() {
          _selectedMaterialId = id;
          _selectedMaterialName = mat['name'] as String?;
          _selectedUnit = (mat['unit'] as String?) ?? 'Bags';
        });
      },
      validator: (v) => v == null ? 'Select a material' : null,
    );
  }

  /// Unit is auto-selected from the material, shown as a read-only chip.
  Widget _buildUnitChip() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.roseGold.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          _selectedUnit,
          style: const TextStyle(
            color: AppColors.roseGold,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFB77B57), Color(0xFFD4A574)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.roseGold.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _generating ? null : _generate,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        icon: _generating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.picture_as_pdf, color: Colors.white),
        label: Text(
          _generating ? 'Generating…' : 'Generate Loading Memo',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.roseGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.roseGold,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Preview Card — shows how the PDF sentence will look
// ─────────────────────────────────────────────────────────────────────────────
class _PreviewCard extends StatelessWidget {
  final DateTime date;
  final String vehicleNumber;
  final String? materialName;
  final String quantity;
  final String unit;

  const _PreviewCard({
    required this.date,
    required this.vehicleNumber,
    required this.materialName,
    required this.quantity,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final vNum = vehicleNumber.isEmpty ? 'XXXXXXXXXX' : vehicleNumber.toUpperCase();
    final mat = materialName ?? '_______________';
    final qty = quantity.isEmpty ? '___' : quantity;
    final dateStr = DateFormat('dd/MM/yyyy').format(date);

    final sentence =
        'In the vehicle number, $vNum, $qty $unit of $mat to be loaded.';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header strip
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF2D6EA4),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: const Row(
              children: [
                Icon(Icons.visibility_outlined, color: Colors.white70, size: 14),
                SizedBox(width: 6),
                Text(
                  'MEMO PREVIEW',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // White area simulating the PDF page
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Company header row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo placeholder
                    Container(
                      width: 52,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B6B6B),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.image, color: Colors.white54, size: 22),
                    ),
                    const SizedBox(width: 10),
                    // Company info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FELSHIA TRADERS',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              fontSize: 15,
                            ),
                          ),
                          Divider(color: Colors.black54, thickness: 0.8, height: 6),
                          const Text(
                            'since 1996\nph: 967723589',
                            style: TextStyle(
                              color: Colors.black54,
                              fontStyle: FontStyle.italic,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Divider(color: Colors.blueGrey.shade400, thickness: 1, height: 12),
                // Date
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'DATE: $dateStr',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Sentence
                Text(
                  sentence,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
