import 'package:flutter/material.dart';

/// A page route that is simply THERE — no transition, and opaque from the very
/// first frame.
///
/// The app already replaced the transition BUILDER app-wide (a no-op builder in
/// `AniLocalApp`'s `pageTransitionsTheme`), so navigation looked instant. It
/// wasn't opaque, though: `MaterialPageRoute` keeps a 300ms
/// `transitionDuration` regardless of what the builder draws, and
/// `TransitionRoute` marks the route's overlay entry **non-opaque for the
/// duration of the animation**, restoring `opaque` only on
/// `AnimationStatus.completed`. That is deliberate — it is what lets a real
/// transition cross-fade against the page underneath.
///
/// With the header hoist, pages stopped carrying their own `Scaffold`: the shell
/// owns the only one. So during those 300ms there was nothing opaque in the
/// route itself, and the page below kept painting straight through the arriving
/// one — the library visibly showing under the detail page on the way in, and
/// under the library on the way back. (Measured: the page below stayed on-stage
/// for ~3 frames and only went offstage after ~400ms.)
///
/// Zeroing the duration fixes it at the cause rather than papering over it: the
/// animation completes immediately, the entry is opaque on the first frame, and
/// the Navigator stops painting everything beneath. No background needs to be
/// bolted onto each page, and no transition is introduced to cover the gap — the
/// shell's chassis is already behind everything, so there is never an unpainted
/// frame.
class InstantPageRoute<T> extends MaterialPageRoute<T> {
  InstantPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}
