import 'package:flutter/material.dart';

import '../../data/place_models.dart';
import 'map_style.dart';

/// Name a circle, pick what it is, and set how big it is.
///
/// The radius slider is the part that matters and it is the part people get
/// wrong, so it works hard to stop them: the value is shown in the units they
/// think in, the floor is enforced with an explanation rather than a silent
/// clamp, and the circle behind the sheet resizes live as the slider moves.
/// Somebody dragging it can *see* the circle swallow the neighbours' houses,
/// which no amount of help text achieves.
///
/// The sheet does not own the map. It reports the radius as it changes and
/// the map screen redraws — that inversion is what lets the preview be the
/// real circle on the real map rather than a diagram of one.
class PlaceEditorSheet extends StatefulWidget {
  const PlaceEditorSheet({
    super.key,
    required this.place,
    required this.palette,
    required this.onSave,
    this.onDelete,
    this.onRadiusChanged,
  });

  /// The place being edited. A new one arrives with an empty id and the
  /// coordinates of wherever the map was long-pressed.
  final FamilyPlace place;

  final MapPalette palette;

  /// Returns false to keep the sheet open — a validation failure from the
  /// server should not throw away what somebody typed.
  final Future<bool> Function(FamilyPlace place) onSave;

  final Future<void> Function()? onDelete;

  /// Fired on every slider frame so the map can redraw the circle.
  final void Function(double metres)? onRadiusChanged;

  @override
  State<PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends State<PlaceEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.place.name == 'Place' ? '' : widget.place.name);

  late String _kind = widget.place.kind;
  late double _radius = widget.place.radiusMetres;
  late bool _arrive = widget.place.notifyOnArrive;
  late bool _leave = widget.place.notifyOnLeave;

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isNew => widget.place.id.isEmpty;

  /// Suggest a name from the kind, but only while the field is untouched.
  ///
  /// Nine places out of ten are called what they are, and typing "Home" into
  /// a box after tapping a button labelled "Home" is a pointless keystroke.
  /// Overwriting something somebody actually typed would be much worse than
  /// the keystroke, so this only ever fills an empty field.
  void _pickKind(String kind) {
    setState(() {
      _kind = kind;

      if (_name.text.trim().isEmpty && kind != 'custom') {
        _name.text = PlaceKinds.label(kind);
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();

    if (name.isEmpty) {
      setState(() {});

      return;
    }

    setState(() => _saving = true);

    final ok = await widget.onSave(
      widget.place.copyWith(
        name: name,
        kind: _kind,
        radiusMetres: _radius,
        notifyOnArrive: _arrive,
        notifyOnLeave: _leave,
      ),
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final empty = _name.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Icon(
                        PlaceKinds.icon(_kind),
                        size: 20,
                        color: PlaceKinds.tint(_kind),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        _isNew ? 'New place' : 'Edit place',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (widget.onDelete != null)
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await widget.onDelete!();

                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                          color: const Color(0xFFE5484D),
                          tooltip: 'Delete',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // --- kind ---------------------------------------------------
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: FamilyPlace.kinds.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 9),
                    itemBuilder: (context, index) {
                      final kind = FamilyPlace.kinds[index];

                      return _KindTile(
                        kind: kind,
                        palette: palette,
                        selected: _kind == kind,
                        onTap: () => _pickKind(kind),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // --- name ---------------------------------------------------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: TextField(
                    controller: _name,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: "Nani's house",
                      counterText: '',
                      errorText: empty && _saving ? 'Give it a name' : null,
                      labelStyle: TextStyle(color: palette.textMuted),
                      hintStyle: TextStyle(
                        color: palette.textMuted.withValues(alpha: 0.6),
                      ),
                      filled: true,
                      fillColor: palette.textMuted.withValues(alpha: 0.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // --- radius -------------------------------------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Size',
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _radius < 1000
                                ? '${_radius.round()} m'
                                : '${(_radius / 1000).toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _radius,
                        min: FamilyPlace.minRadius,
                        max: FamilyPlace.maxRadius,

                        /*
                         | Coarse on purpose.
                         |
                         | Twenty-four stops across the whole range, which
                         | lands on round-ish numbers and makes the slider
                         | feel like it has detents. A continuous slider here
                         | invites people to fiddle towards a precision the
                         | underlying GPS cannot deliver — 147 m is not a
                         | more accurate answer than 150 m, it is the same
                         | answer typed more carefully.
                         */
                        divisions: 24,
                        activeColor: PlaceKinds.tint(_kind),
                        onChanged: (value) {
                          setState(() => _radius = value);
                          widget.onRadiusChanged?.call(value);
                        },
                      ),
                      Text(
                        'Anyone inside this circle for a minute counts as '
                        'being here. Below ${FamilyPlace.minRadius.round()} m, '
                        'GPS cannot tell inside from outside reliably.',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // --- notifications ------------------------------------------
                _Switch(
                  palette: palette,
                  label: 'Tell me when someone arrives',
                  value: _arrive,
                  onChanged: (v) => setState(() => _arrive = v),
                ),
                _Switch(
                  palette: palette,
                  label: 'Tell me when someone leaves',
                  value: _leave,
                  onChanged: (v) => setState(() => _leave = v),
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: PlaceKinds.tint(_kind),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isNew ? 'Add place' : 'Save changes',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final String kind;
  final MapPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = PlaceKinds.tint(kind);

    return Material(
      color: selected
          ? tint.withValues(alpha: 0.14)
          : palette.textMuted.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 74,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? tint : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PlaceKinds.icon(kind),
                size: 21,
                color: selected ? tint : palette.textMuted,
              ),
              const SizedBox(height: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  kind == 'custom' ? 'Other' : PlaceKinds.label(kind),
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? tint : palette.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final MapPalette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      activeThumbColor: palette.accent,
      title: Text(
        label,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
