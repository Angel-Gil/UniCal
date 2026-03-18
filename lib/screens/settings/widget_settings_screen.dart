import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../services/widget_service.dart';

class WidgetSettingsScreen extends StatefulWidget {
  const WidgetSettingsScreen({super.key});

  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  // Valores por defecto
  String _displayMode = 'next_class'; // 'next_class' o 'daily_schedule'
  Color _backgroundColor = const Color(0xFF1E1E2E);
  double _backgroundOpacity = 1.0;
  Color _titleColor = const Color(0xFF8B9FEF);
  Color _subjectColor = const Color(0xFFFFFFFF);
  Color _timeColor = const Color(0xFFB0B0C0);

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await HomeWidget.getWidgetData<String>('widget_display_mode', defaultValue: 'next_class');
    
    final bgHex = await HomeWidget.getWidgetData<String>('widget_bg_color', defaultValue: '#1E1E2E');
    final bgOpacity = await HomeWidget.getWidgetData<double>('widget_bg_opacity', defaultValue: 1.0);
    final titleHex = await HomeWidget.getWidgetData<String>('widget_text_color_title', defaultValue: '#8B9FEF');
    final subjectHex = await HomeWidget.getWidgetData<String>('widget_text_color_subject', defaultValue: '#FFFFFF');
    final timeHex = await HomeWidget.getWidgetData<String>('widget_text_color_time', defaultValue: '#B0B0C0');

    setState(() {
      _displayMode = mode ?? 'next_class';
      _backgroundColor = _colorFromHex(bgHex ?? '#1E1E2E');
      _backgroundOpacity = bgOpacity ?? 1.0;
      _titleColor = _colorFromHex(titleHex ?? '#8B9FEF');
      _subjectColor = _colorFromHex(subjectHex ?? '#FFFFFF');
      _timeColor = _colorFromHex(timeHex ?? '#B0B0C0');
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await HomeWidget.saveWidgetData<String>('widget_display_mode', _displayMode);
    await HomeWidget.saveWidgetData<String>('widget_bg_color', _colorToHex(_backgroundColor));
    await HomeWidget.saveWidgetData<double>('widget_bg_opacity', _backgroundOpacity);
    await HomeWidget.saveWidgetData<String>('widget_text_color_title', _colorToHex(_titleColor));
    await HomeWidget.saveWidgetData<String>('widget_text_color_subject', _colorToHex(_subjectColor));
    await HomeWidget.saveWidgetData<String>('widget_text_color_time', _colorToHex(_timeColor));

    // Force widget update
    await WidgetService.updateNextClassWidget();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración del widget guardada')),
      );
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Color _colorFromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  void _showColorPicker(String title, Color currentColor, void Function(Color) onApply) {
    Color pickerColor = currentColor;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              pickerColor = color;
            },
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
          ),
          ElevatedButton(
            child: const Text('Guardar'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Apply color change after dialog is closed
              setState(() {
                onApply(pickerColor);
              });
              _saveSettings();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personalizar Widget'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Modo de visualización',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RadioListTile<String>(
            title: const Text('Próxima clase (Por defecto)'),
            subtitle: const Text('Muestra solo la siguiente clase o evento'),
            value: 'next_class',
            groupValue: _displayMode,
            onChanged: (value) {
              setState(() => _displayMode = value!);
              _saveSettings();
            },
          ),
          RadioListTile<String>(
            title: const Text('Horario del día'),
            subtitle: const Text('Muestra todas las clases programadas para hoy'),
            value: 'daily_schedule',
            groupValue: _displayMode,
            onChanged: (value) {
              setState(() => _displayMode = value!);
              _saveSettings();
            },
          ),
          const Divider(height: 32),
          const Text(
            'Fondo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Color de fondo'),
            trailing: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _backgroundColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey),
              ),
            ),
            onTap: () => _showColorPicker('Color de fondo', _backgroundColor, (c) => _backgroundColor = c),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Opacidad:'),
                Expanded(
                  child: Slider(
                    value: _backgroundOpacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: '${(_backgroundOpacity * 100).round()}%',
                    onChanged: (value) {
                      setState(() => _backgroundOpacity = value);
                    },
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ),
                Text('${(_backgroundOpacity * 100).round()}%'),
              ],
            ),
          ),
          const Divider(height: 32),
          const Text(
            'Textos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Color del Título'),
            subtitle: const Text('Ej: "UniCal"'),
            trailing: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _titleColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey),
              ),
            ),
            onTap: () => _showColorPicker('Color del Título', _titleColor, (c) => _titleColor = c),
          ),
          ListTile(
            title: const Text('Color de la Materia'),
            trailing: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _subjectColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey),
              ),
            ),
            onTap: () => _showColorPicker('Color de la Materia', _subjectColor, (c) => _subjectColor = c),
          ),
          ListTile(
            title: const Text('Color de la Hora/Aula'),
            trailing: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _timeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey),
              ),
            ),
            onTap: () => _showColorPicker('Color de la Hora', _timeColor, (c) => _timeColor = c),
          ),
          const SizedBox(height: 32),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar valores por defecto'),
              onPressed: () {
                setState(() {
                  _displayMode = 'next_class';
                  _backgroundColor = const Color(0xFF1E1E2E);
                  _backgroundOpacity = 1.0;
                  _titleColor = const Color(0xFF8B9FEF);
                  _subjectColor = const Color(0xFFFFFFFF);
                  _timeColor = const Color(0xFFB0B0C0);
                });
                _saveSettings();
              },
            ),
          ),
        ],
      ),
    );
  }
}
