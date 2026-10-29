/// The assistant's three calls (`/ai/*`).
///
/// Online only, and optional by design. The analysis is an extra on top of
/// what the device already works out for itself, so every failure here has
/// the same consequence: the screen keeps the offline analysis and says the
/// assistant could not answer. Nothing is queued for later — an analysis of
/// last week's numbers delivered next Tuesday is worse than none.
///
/// The server answers 503 for four different situations (no key, provider
/// down, the model refused, the answer failed the religious check). They are
/// one kind here on purpose: the user can do nothing different about any of
/// them, and the reason belongs in the server's log, not on a phone screen.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/ai_analysis.dart';
import '../domain/analysis_facts.dart';

enum AiErrorKind {
  /// No connection, a timeout, or the server never answered.
  network,

  /// The session is gone; the user has to sign in again.
  unauthorized,

  /// The assistant could not answer. Not the user's fault and not fixable
  /// from here — the offline analysis stands.
  unavailable,

  /// Today's analyses are used up.
  quotaExceeded,

  /// There was not enough recorded to analyse (the server's 422).
  notEnoughData,
}

class AiApiException implements Exception {
  const AiApiException(this.kind);

  final AiErrorKind kind;

  @override
  String toString() => 'AiApiException($kind)';
}

class AiApi {
  const AiApi(this._dio);

  final Dio _dio;

  /// Asks for an analysis of [facts] and returns the stored proposal.
  Future<AiProposal> requestAnalysis(AnalysisFacts facts) async {
    final data = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/ai/analysis',
        data: facts.toJson(),
        // One analysis is a model call: slower than any other request this
        // app makes, and the default 15s receive timeout would abandon a
        // call the server is still paying for.
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      ),
    );
    return AiProposal.fromJson(data!);
  }

  /// The proposals this account already has, newest first.
  Future<List<AiProposal>> proposals({String? agent, int limit = 20}) async {
    final data = await _send(
      () => _dio.get<List<dynamic>>(
        '/ai/proposals',
        queryParameters: {
          if (agent != null) 'agent': agent,
          'limit': limit,
        },
      ),
    );
    return [
      for (final entry in data ?? const [])
        if (entry is Map<String, dynamic>) AiProposal.fromJson(entry),
    ];
  }

  /// Records what the user did with a proposal.
  ///
  /// This does not create anything: an accepted widget is written on the
  /// device and arrives at the server through the ordinary sync. All this
  /// call does is let the server know its suggestion was any good.
  Future<void> record(
    String proposalId,
    AiProposalOutcome outcome, {
    Map<String, dynamic>? appliedDiff,
  }) async {
    await _send(
      () => _dio.patch<Map<String, dynamic>>(
        '/ai/proposals/$proposalId',
        data: {
          'status': outcome.wire,
          if (appliedDiff != null) 'applied_diff': appliedDiff,
        },
      ),
    );
  }

  static Future<T?> _send<T>(Future<Response<T>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (error) {
      throw AiApiException(_kindOf(error));
    }
  }

  static AiErrorKind _kindOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return AiErrorKind.network;
    }
    return switch (error.response?.statusCode ?? 0) {
      401 => AiErrorKind.unauthorized,
      429 => AiErrorKind.quotaExceeded,
      422 => AiErrorKind.notEnoughData,
      503 => AiErrorKind.unavailable,
      _ => AiErrorKind.network,
    };
  }
}

final aiApiProvider = Provider<AiApi>((ref) => AiApi(ref.watch(dioProvider)));

/// The agent these screens talk to. The server keys its daily quota by
/// agent name, so this string has to match `app.ai.agents.analyst`.
const String analystAgent = 'analyst';
