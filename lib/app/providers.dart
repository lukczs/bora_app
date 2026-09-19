import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/bora_store.dart';

/// Assistir a este provider redesenha a tela a cada mudança nos dados.
final storeProvider =
    ChangeNotifierProvider<BoraStore>((ref) => BoraStore(Supabase.instance.client));
