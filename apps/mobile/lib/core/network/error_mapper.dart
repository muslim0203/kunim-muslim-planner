import 'package:dio/dio.dart';

/// Failure classification for API calls. Deliberately has no Phase-1 auth
/// concepts (token refresh, etc.) — that lives in `core/auth/` later.
///
/// Kept as a manually-written sealed class (not `freezed`) so this file
/// compiles with zero code generation, even before `build_runner` has run.
sealed class ApiFailure {
  const ApiFailure({this.message, this.statusCode});

  /// Optional human-unreadable diagnostic message (never shown to the
  /// user directly — screens must map this to an `AppLocalizations` string).
  final String? message;
  final int? statusCode;
}

final class NetworkFailure extends ApiFailure {
  const NetworkFailure({super.message});
}

final class TimeoutFailure extends ApiFailure {
  const TimeoutFailure({super.message});
}

final class UnauthorizedFailure extends ApiFailure {
  const UnauthorizedFailure({super.message, super.statusCode});
}

final class ServerFailure extends ApiFailure {
  const ServerFailure({super.message, super.statusCode});
}

final class UnknownFailure extends ApiFailure {
  const UnknownFailure({super.message, super.statusCode});
}

/// Maps a [DioException] to an [ApiFailure]. UI code should switch on the
/// sealed type (exhaustive `switch`) rather than inspecting Dio directly.
ApiFailure mapDioExceptionToApiFailure(DioException exception) {
  switch (exception.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return TimeoutFailure(message: exception.message);
    case DioExceptionType.connectionError:
      return NetworkFailure(message: exception.message);
    case DioExceptionType.badResponse:
      final statusCode = exception.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        return UnauthorizedFailure(
          message: exception.message,
          statusCode: statusCode,
        );
      }
      if (statusCode != null && statusCode >= 500) {
        return ServerFailure(
          message: exception.message,
          statusCode: statusCode,
        );
      }
      return UnknownFailure(
        message: exception.message,
        statusCode: statusCode,
      );
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return UnknownFailure(message: exception.message);
  }
}
