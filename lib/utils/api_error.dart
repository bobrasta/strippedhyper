import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../theme/app_colors.dart';

/// Converts a caught exception into a short, user-readable string.
String friendlyError(Object e) {
  if (e is DioException) {
    // Laravel sends {"message": "..."} for both abort_if(..., 'reason')
    // calls and validation failures — prefer that real, specific reason
    // over a generic status-code message wherever the backend supplied
    // one (a 403 in this codebase is almost always a deliberate, worded
    // abort_if, not a bare access-denied).
    final serverMessage = _serverMessage(e);
    return switch (e.type) {
      DioExceptionType.connectionTimeout =>
        'Cannot connect to the server. Check your network.',
      DioExceptionType.receiveTimeout =>
        'The server is taking too long to respond. Please try again.',
      DioExceptionType.sendTimeout =>
        'Request timed out sending data. Please try again.',
      DioExceptionType.connectionError =>
        'Cannot reach the server. Make sure the API is running.',
      DioExceptionType.badResponse => () {
        final status = e.response?.statusCode;
        if (status == 401) return 'Session expired. Please log in again.';
        if (status == 403) {
          // Backend abort_if() reasons already read naturally ("Only the CTO
          // or Director can..."); prefix rather than duplicate "Access
          // Denied" into the sentence itself.
          final reason = serverMessage ?? 'You don\'t have permission to do this.';
          return 'Access Denied: $reason';
        }
        if (serverMessage != null) return serverMessage;
        if (status == 404) return 'Resource not found on the server.';
        if (status != null && status >= 500) return 'Server error ($status). Contact support.';
        return 'Unexpected server response ($status).';
      }(),
      DioExceptionType.cancel => 'Request was cancelled.',
      _ => 'Something went wrong. Please try again.',
    };
  }
  return e.toString().replaceAll('Exception: ', '');
}

String? _serverMessage(DioException e) {
  var data = e.response?.data;
  // File downloads use ResponseType.bytes, so an error body arrives as raw
  // bytes rather than a decoded map — decode it to reach the message.
  if (data is List<int>) {
    try {
      data = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
  }
  if (data is Map && data['message'] is String) return data['message'] as String;
  return null;
}

/// Show a SnackBar error toast. Use instead of inline error text.
void showErrorToast(BuildContext context, Object error) {
  final msg = friendlyError(error);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.error_outline, color: Colors.white, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
    ]),
    backgroundColor: AppColors.coral,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ));
}

/// Show a success toast.
void showSuccessToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
    ]),
    backgroundColor: AppColors.teal,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 3),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ));
}
