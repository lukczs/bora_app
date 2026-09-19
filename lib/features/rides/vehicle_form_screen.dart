import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';

class VehicleFormScreen extends ConsumerStatefulWidget {
  const VehicleFormScreen({super.key, this.vehicleId});
  final String? vehicleId;
  @override
  ConsumerState<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends ConsumerState<VehicleFormScreen> {
  final _form = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  int _seats = 3;
  bool _loading = false;

  bool get _editing => widget.vehicleId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final v = ref.read(storeProvider).myVehicles.firstWhere((x) => x.id == widget.vehicleId);
      _plate.text = v.plate;
      _brand.text = v.brand;
      _model.text = v.model;
      _color.text = v.color;
      _seats = v.seats;
    }
  }

  @override
  void dispose() {
    _plate.dispose();
    _brand.dispose();
    _model.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).saveVehicle(
            vehicleId: widget.vehicleId,
            plate: _plate.text,
            brand: _brand.text.trim(),
            model: _model.text.trim(),
            color: _color.text.trim().toLowerCase(),
            seats: _seats,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).deleteVehicle(widget.vehicleId!);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Preencha este campo.' : null;

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: _editing ? 'Editar carro' : 'Cadastrar meu carro',
      subtitle: 'Passageiros veem o modelo, a cor e a placa para conferir o carro antes de embarcar.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoraButton(label: 'Salvar carro', loading: _loading, onPressed: _save),
          if (_editing)
            TextButton(
              onPressed: _loading ? null : _delete,
              child: const Text('Excluir carro', style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
      child: Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(7),
              ],
              decoration: const InputDecoration(labelText: 'Placa', hintText: 'ABC1D23'),
              validator: (v) =>
                  RegExp(r'^[A-Za-z]{3}[0-9][A-Za-z0-9][0-9]{2}$').hasMatch((v ?? '').trim())
                      ? null
                      : 'Placa inválida. Use o formato ABC1D23 ou ABC1234.',
            ),
            const SizedBox(height: 14),
            TextFormField(
                controller: _brand,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Marca', hintText: 'Fiat'),
                validator: _required),
            const SizedBox(height: 14),
            TextFormField(
                controller: _model,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Modelo', hintText: 'Argo'),
                validator: _required),
            const SizedBox(height: 14),
            TextFormField(
                controller: _color,
                decoration: const InputDecoration(labelText: 'Cor', hintText: 'preto'),
                validator: _required),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text('Vagas para passageiros',
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  onPressed: _seats > 1 ? () => setState(() => _seats--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_seats',
                    style: const TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
                IconButton(
                  onPressed: _seats < 6 ? () => setState(() => _seats++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
