import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/join/cray_api.dart';
import '../../domain/wallet/wallet.dart';
import '../join/join_controller.dart';

/// The wallet API, when the signed-in account is one that has a wallet. A
/// stylist does not: `my_wallet` is keyed on the caller's own customer id and
/// would return zeros, which is a worse answer than no screen.
final walletApiProvider = Provider<WalletApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is WalletApi ? api as WalletApi : null;
});

/// Balance and history, read together. Money is **never** served from the cache
/// (RULES 5): a stale balance is a number the customer will plan a haircut
/// around. Offline, this screen says it could not load - it does not guess.
final walletProvider = FutureProvider<WalletView>((ref) async {
  final api = ref.watch(walletApiProvider);
  if (api == null) return const WalletView(WalletSummary.empty, []);
  final summary = await api.wallet();
  final history = await api.walletHistory();
  return WalletView(summary, history);
});

class WalletView {
  const WalletView(this.summary, this.history);

  final WalletSummary summary;
  final List<WalletEntry> history;
}

/// What the server says this amount is worth. Re-quoted on every change, and
/// never computed here: an app that works out its own bonus is an app that can
/// promise one the ledger will refuse.
final topupQuoteProvider =
    FutureProvider.family<TopupQuote, int>((ref, amountPaise) async {
  final api = ref.watch(walletApiProvider);
  if (api == null) throw const CrayApiException(CrayErrorKind.server);
  return api.topupQuote(amountPaise);
});
