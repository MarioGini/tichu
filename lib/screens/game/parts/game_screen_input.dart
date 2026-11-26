part of '../game_screen.dart';

/// Keyboard shortcuts and schupf slot / cursor handling.
mixin _GameScreenInput on _GameScreenStateBase {
  @override
  void _requestKeyboardFocus() {
    if (!mounted) return;
    _schupfFocusNode.requestFocus();
  }

  @override
  void _handleShortcutEnter() {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (_shouldShowGrandTichuDecision(snapshot)) {
      unawaited(_submitGrandTichuDecision(!_grandTichuSelectNo));
      return;
    }

    if (_trySchupfCursorAssign(snapshot)) return;

    // Acknowledge schupf receipts with Enter.
    if (snapshot.schupfReceipts.isNotEmpty && !_schupfAckPending) {
      unawaited(_acknowledgeSchupfReceipts());
      return;
    }

    if (!_isSelfManual || snapshot.phase != GamePhase.play) {
      return;
    }
    final pendingReceipts =
        _schupfAckPending || snapshot.schupfReceipts.isNotEmpty;
    final canPlay = !pendingReceipts && _canPlaySelected(snapshot);
    if (!canPlay) return;
    unawaited(_playSelected());
  }

  @override
  void _handleShortcutLeft() {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (_shouldShowGrandTichuDecision(snapshot)) {
      setState(() {
        _grandTichuSelectNo = true;
      });
      return;
    }

    _moveSchupfCursor(snapshot, -1);
  }

  @override
  void _handleShortcutRight() {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (_shouldShowGrandTichuDecision(snapshot)) {
      setState(() {
        _grandTichuSelectNo = false;
      });
      return;
    }

    _moveSchupfCursor(snapshot, 1);
  }

  /// Returns the list of hand cards not yet assigned to a schupf slot,
  /// or `null` if schupf cursor navigation is not applicable.
  List<Card>? _schupfAvailableCards(PlayerSnapshot snapshot) {
    final isSchupfActive =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    if (!isSchupfActive) return null;
    if (!_hasKeyboardForSchupf) return null;

    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) return null;

    final selectedCards = <Card>{
      ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
    };
    final available = _hand.where((c) => !selectedCards.contains(c)).toList();
    return available.isEmpty ? null : available;
  }

  /// Assigns the card under the schupf cursor to the next empty slot.
  /// Returns `true` if the event was handled.
  bool _trySchupfCursorAssign(PlayerSnapshot snapshot) {
    final isSchupfActive =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    if (!isSchupfActive) return false;
    if (!_hasKeyboardForSchupf) return false;

    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) {
      unawaited(_submitSchupf());
      return true;
    }

    final available = _schupfAvailableCards(snapshot);
    if (available == null) return true;

    final cursor = (_schupfCursorIndex ?? (available.length - 1)).clamp(
      0,
      available.length - 1,
    );
    final card = available[cursor];
    if (_schupfToRight == null) {
      _setSchupfSlot(SchupfSlot.right, card);
    } else if (_schupfToPartner == null) {
      _setSchupfSlot(SchupfSlot.partner, card);
    } else if (_schupfToLeft == null) {
      _setSchupfSlot(SchupfSlot.left, card);
    }
    return true;
  }

  /// Moves the schupf cursor by [delta] (-1 = left, +1 = right).
  void _moveSchupfCursor(PlayerSnapshot snapshot, int delta) {
    final available = _schupfAvailableCards(snapshot);
    if (available == null) return;

    final cursor = _schupfCursorIndex ?? (available.length - 1);
    setState(() {
      _schupfCursorIndex = (cursor + delta).clamp(0, available.length - 1);
    });
  }

  @override
  void _setSchupfSlot(SchupfSlot slot, Card card) {
    setState(() {
      if (_schupfToLeft == card) _schupfToLeft = null;
      if (_schupfToPartner == card) _schupfToPartner = null;
      if (_schupfToRight == card) _schupfToRight = null;

      switch (slot) {
        case SchupfSlot.left:
          _schupfToLeft = card;
        case SchupfSlot.partner:
          _schupfToPartner = card;
        case SchupfSlot.right:
          _schupfToRight = card;
      }
      if (_hasKeyboardForSchupf) {
        _syncSchupfCursor(defaultToRightMost: true);
      } else {
        _schupfCursorIndex = null;
      }
    });
  }

  @override
  void _clearSchupfSlot(SchupfSlot slot) {
    setState(() {
      switch (slot) {
        case SchupfSlot.left:
          _schupfToLeft = null;
        case SchupfSlot.partner:
          _schupfToPartner = null;
        case SchupfSlot.right:
          _schupfToRight = null;
      }
      if (_hasKeyboardForSchupf) {
        _syncSchupfCursor(defaultToRightMost: true);
      } else {
        _schupfCursorIndex = null;
      }
    });
  }

  @override
  void _syncSchupfCursor({required bool defaultToRightMost}) {
    if (!_hasKeyboardForSchupf) {
      _schupfCursorIndex = null;
      return;
    }
    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) {
      _schupfCursorIndex = null;
      return;
    }

    final selectedCards = <Card>{
      ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
    };
    final available = _hand.where((c) => !selectedCards.contains(c)).length;
    if (available == 0) {
      _schupfCursorIndex = null;
      return;
    }

    if (_schupfCursorIndex == null) {
      _schupfCursorIndex = defaultToRightMost ? available - 1 : 0;
      return;
    }
    _schupfCursorIndex = _schupfCursorIndex!.clamp(0, available - 1);
  }

  @override
  bool get _hasKeyboardForSchupf {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery != null) {
      final shortestSide = math.min(
        mediaQuery.size.width,
        mediaQuery.size.height,
      );
      if (shortestSide < 600) {
        return false;
      }
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }
}
