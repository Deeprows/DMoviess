import 'package:flutter/material.dart';

import '../services/push_service.dart';
import '../utils/l10n.dart';

/// On/off switches for each push topic (Settings > Notifications).
class PushSwitches extends StatefulWidget {
  const PushSwitches({super.key});

  @override
  State<PushSwitches> createState() => _PushSwitchesState();
}

class _PushSwitchesState extends State<PushSwitches> {
  final Map<PushTopic, bool> _on = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final t in PushTopic.values) {
      _on[t] = await PushService.instance.isEnabled(t);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final t in PushTopic.values)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _on[t] ?? true,
            onChanged: (value) async {
              setState(() => _on[t] = value);
              await PushService.instance.setEnabled(t, value);
            },
            title: Text(t.title.tr),
            subtitle: Text(t.subtitle.tr),
            secondary: Icon(t.icon),
          ),
      ]);
}
