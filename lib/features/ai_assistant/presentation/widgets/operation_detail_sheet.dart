import 'package:flutter/material.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation.dart';

class OperationDetailSheet extends StatefulWidget {
  final AiOperation operation;
  final void Function(Map<String, dynamic> newParams) onSave;

  const OperationDetailSheet({
    super.key,
    required this.operation,
    required this.onSave,
  });

  @override
  State<OperationDetailSheet> createState() => _OperationDetailSheetState();
}

class _OperationDetailSheetState extends State<OperationDetailSheet> {
  late Map<String, dynamic> _params;
  final _formKey = GlobalKey<FormState>();

  bool _hasTimeFields = false;
  DateTime? _startDt;
  DateTime? _endDt;
  int _durationMinutes = 0;
  late TextEditingController _durationCtrl;

  @override
  void initState() {
    super.initState();
    _params = Map<String, dynamic>.from(widget.operation.params);
    _durationCtrl = TextEditingController();
    _initTimeFields();
  }

  void _initTimeFields() {
    final dueDate = _params['dueDate'] as String?;
    final dueTime = _params['dueTime'] as String?;
    final reminderAt = _params['reminderAt'] as String?;
    final expectedMinutes = _params['expectedMinutes'] as int?;

    _hasTimeFields = dueDate != null || reminderAt != null;

    if (reminderAt != null) {
      _startDt = AppTime.parseSelectedIso(reminderAt);
    }

    if (dueDate != null && dueTime != null) {
      _endDt = _tryParse(dueDate, dueTime);
    } else if (dueDate != null) {
      _endDt = _tryParse(dueDate, '00:00');
    }

    _durationMinutes = expectedMinutes ??
        (_startDt != null && _endDt != null
            ? _endDt!.difference(_startDt!).inMinutes
            : 0);

    _durationCtrl.text =
        _durationMinutes > 0 ? _durationMinutes.toString() : '';
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    super.dispose();
  }

  void _syncTimeFieldsToParams() {
    if (_startDt != null) {
      _params['reminderAt'] =
          '${_fmtDate(_startDt!)}T${_fmtTime(_startDt!)}:00';
    } else {
      _params.remove('reminderAt');
    }

    if (_endDt != null) {
      _params['dueDate'] = _fmtDate(_endDt!);
      _params['dueTime'] = _fmtTime(_endDt!);
    } else {
      _params.remove('dueDate');
      _params.remove('dueTime');
    }

    _params['expectedMinutes'] = _durationMinutes > 0 ? _durationMinutes : null;
    if (_params['expectedMinutes'] == null) {
      _params.remove('expectedMinutes');
    }
  }

  // ── Picker handlers ──────────────────────────────────────────

  Future<void> _pickStartDate() async {
    final initial = _startDt ?? _endDt ?? AppTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择开始日期',
    );
    if (picked == null) return;
    final newStart = AppTime.create(
      picked.year,
      picked.month,
      picked.day,
      _startDt?.hour ?? 0,
      _startDt?.minute ?? 0,
    );
    setState(() {
      _startDt = newStart;
      _adjustEndFromStart();
    });
  }

  Future<void> _pickStartTime() async {
    final initial = TimeOfDay.fromDateTime(_startDt ?? _endDt ?? AppTime.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '选择开始时间',
    );
    if (picked == null) return;
    final base = _startDt ?? _endDt ?? AppTime.now();
    setState(() {
      _startDt = AppTime.create(
          base.year, base.month, base.day, picked.hour, picked.minute);
      _adjustEndFromStart();
    });
  }

  Future<void> _pickEndDate() async {
    final initial = _endDt ?? _startDt ?? AppTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择截止日期',
    );
    if (picked == null) return;
    final newEnd = AppTime.create(
      picked.year,
      picked.month,
      picked.day,
      _endDt?.hour ?? 0,
      _endDt?.minute ?? 0,
    );
    setState(() {
      _endDt = newEnd;
      _recalcDuration();
    });
  }

  Future<void> _pickEndTime() async {
    final initial = TimeOfDay.fromDateTime(_endDt ?? _startDt ?? AppTime.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '选择截止时间',
    );
    if (picked == null) return;
    final base = _endDt ?? _startDt ?? AppTime.now();
    setState(() {
      _endDt = AppTime.create(
          base.year, base.month, base.day, picked.hour, picked.minute);
      _recalcDuration();
    });
  }

  void _adjustEndFromStart() {
    if (_startDt == null) return;
    if (_durationMinutes > 0) {
      _endDt = _startDt!.add(Duration(minutes: _durationMinutes));
    } else if (_endDt != null && _endDt!.isBefore(_startDt!)) {
      _endDt = _startDt;
      _durationMinutes = 0;
      _durationCtrl.text = '';
    }
  }

  void _recalcDuration() {
    if (_startDt != null && _endDt != null) {
      final diff = _endDt!.difference(_startDt!).inMinutes;
      _durationMinutes = diff > 0 ? diff : 0;
      _durationCtrl.text =
          _durationMinutes > 0 ? _durationMinutes.toString() : '';
    }
  }

  void _onDurationChanged() {
    final text = _durationCtrl.text.trim();
    final parsed = int.tryParse(text);
    setState(() {
      _durationMinutes = parsed ?? 0;
      if (_durationMinutes > 0 && _startDt != null) {
        _endDt = _startDt!.add(Duration(minutes: _durationMinutes));
      } else if (_durationMinutes <= 0) {
        _durationCtrl.text = '';
      }
    });
  }

  void _quickAdjust(int minutes) {
    setState(() {
      if (_startDt != null) {
        _startDt = _startDt!.add(Duration(minutes: minutes));
      }
      if (_endDt != null) {
        _endDt = _endDt!.add(Duration(minutes: minutes));
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '编辑操作',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.operation.typeLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_hasTimeFields) ..._buildTimeSection(isDark),
            if (_hasTimeFields) const SizedBox(height: 16),
            ..._buildFields(isDark),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    if (_hasTimeFields) _syncTimeFieldsToParams();
                    widget.onSave(_params);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isDark ? AppColors.darkAccent : AppColors.lightAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('保存修改'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTimeSection(bool isDark) {
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color:
          isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
    );
    final tileStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: isDark ? AppColors.darkText : AppColors.lightText,
    );

    return [
      Text(
        '时间设置',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
      ),
      const SizedBox(height: 10),

      // ── Start time ──
      Text('开始时间（提醒）', style: labelStyle),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: _pickerTile(
              icon: Icons.calendar_today,
              label: _startDt != null ? _fmtDate(_startDt!) : '选择日期',
              isSet: _startDt != null,
              isDark: isDark,
              onTap: _pickStartDate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _pickerTile(
              icon: Icons.access_time,
              label: _startDt != null ? _fmtTime(_startDt!) : '选择时间',
              isSet: _startDt != null,
              isDark: isDark,
              onTap: _pickStartTime,
            ),
          ),
        ],
      ),
      if (_startDt == null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'AI 未生成开始时间，可手动选择',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade300),
          ),
        ),
      const SizedBox(height: 10),

      // ── End time ──
      Text('截止时间', style: labelStyle),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: _pickerTile(
              icon: Icons.calendar_today,
              label: _endDt != null ? _fmtDate(_endDt!) : '选择日期',
              isSet: _endDt != null,
              isDark: isDark,
              onTap: _pickEndDate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _pickerTile(
              icon: Icons.access_time,
              label: _endDt != null ? _fmtTime(_endDt!) : '选择时间',
              isSet: _endDt != null,
              isDark: isDark,
              onTap: _pickEndTime,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),

      // ── Duration ──
      Text('持续时间（分钟）', style: labelStyle),
      const SizedBox(height: 4),
      Row(
        children: [
          SizedBox(
            width: 100,
            child: TextField(
              controller: _durationCtrl,
              keyboardType: TextInputType.number,
              style: tileStyle.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: '分钟',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              onChanged: (_) => _onDurationChanged(),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            _startDt != null && _durationMinutes > 0
                ? '${_fmtDate(_endDt!)} ${_fmtTime(_endDt!)}'
                : '—',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),

      // ── Quick adjust ──
      Text('快捷调整（开始 & 截止同步偏移）', style: labelStyle),
      const SizedBox(height: 4),
      Row(
        children: [
          _quickBtn('-1h', -60, isDark),
          const SizedBox(width: 6),
          _quickBtn('-30m', -30, isDark),
          const SizedBox(width: 6),
          _quickBtn('-5m', -5, isDark),
          const SizedBox(width: 6),
          _quickBtn('+5m', 5, isDark),
          const SizedBox(width: 6),
          _quickBtn('+30m', 30, isDark),
          const SizedBox(width: 6),
          _quickBtn('+1h', 60, isDark),
        ],
      ),
    ];
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required bool isSet,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSet
                ? (isDark ? AppColors.darkAccent : AppColors.lightAccent)
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          color: isSet
              ? (isDark ? AppColors.darkAccent : AppColors.lightAccent)
                  .withOpacity(0.08)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isSet
                    ? (isDark ? AppColors.darkAccent : AppColors.lightAccent)
                    : Colors.grey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSet ? FontWeight.w600 : FontWeight.normal,
                  color: isSet
                      ? (isDark ? AppColors.darkText : AppColors.lightText)
                      : Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickBtn(String label, int offset, bool isDark) {
    return OutlinedButton(
      onPressed: () => _quickAdjust(offset),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  // ── Generic fields ────────────────────────────────────────────

  List<Widget> _buildFields(bool isDark) {
    final fields = <Widget>[];
    final style = TextStyle(
      color: isDark ? AppColors.darkText : AppColors.lightText,
    );

    void addField(String key, String label, {bool isNumber = false}) {
      if (_hasTimeFields &&
          (key == 'dueDate' ||
              key == 'dueTime' ||
              key == 'reminderAt' ||
              key == 'expectedMinutes')) {
        return;
      }
      if (!_params.containsKey(key)) return;
      final controller = TextEditingController(
        text: _params[key]?.toString() ?? '',
      );

      fields.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: style,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          onChanged: (v) {
            if (isNumber) {
              _params[key] = int.tryParse(v);
            } else {
              _params[key] = v;
            }
          },
        ),
      ));
    }

    addField('title', '标题');
    addField('notes', '备注');
    addField('dueDate', '截止日期');
    addField('dueTime', '截止时间');
    addField('expectedMinutes', '预计分钟', isNumber: true);
    addField('frequency', '重复频率');
    addField('interval', '间隔', isNumber: true);
    addField('name', '清单名称');
    addField('listId', '清单名称');

    return fields;
  }

  // ── Helpers ───────────────────────────────────────────────────

  DateTime? _tryParse(String date, String time) {
    try {
      final dateParts = date.split('-');
      final timeParts = time.split(':');
      return AppTime.create(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _fmtDate(DateTime dt) => AppTime.formatDate(dt);

  String _fmtTime(DateTime dt) => AppTime.formatTime(dt);
}

void showOperationDetailSheet(
  BuildContext context, {
  required AiOperation operation,
  required void Function(Map<String, dynamic>) onSave,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor:
        isDark ? AppColors.darkBackground : AppColors.lightBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: OperationDetailSheet(
        operation: operation,
        onSave: onSave,
      ),
    ),
  );
}
