/// 统一的结果与异常模型。
///
/// 所有领域层方法优先返回 [Result]，让错误成为类型的一部分，
/// 避免裸抛异常穿透到 UI 层。
library;

/// 应用内可预期异常的基类。
///
/// [code] 用于 UI/日志定位错误类别；[message] 面向开发者，
/// 不保证适合直接展示给用户。
sealed class AppException implements Exception {
  const AppException(this.code, this.message);

  /// 错误类别码，如 `import.duplicate`、`parse.epub`。
  final String code;

  /// 面向开发者的错误描述。
  final String message;

  @override
  String toString() => 'AppException($code): $message';
}

/// 文件导入相关错误。
class ImportException extends AppException {
  const ImportException(super.code, super.message);
}

/// EPUB/文档解析错误。
class ParseException extends AppException {
  const ParseException(super.code, super.message);
}

/// 数据库/存储错误。
class StorageException extends AppException {
  const StorageException(super.code, super.message);
}

/// 通用结果类型：成功携带 [data]，失败携带 [AppException]。
sealed class Result<T> {
  const Result();

  /// 构造成功结果。
  const factory Result.ok(T data) = Ok<T>;

  /// 构造失败结果。
  const factory Result.failure(AppException error) = Failure<T>;

  /// 成功时返回数据，失败时返回 null。
  T? get dataOrNull => switch (this) {
        Ok<T>(:final data) => data,
        Failure<T>() => null,
      };

  /// 模式匹配式消费：分别处理成功与失败。
  R when<R>({
    required R Function(T data) ok,
    required R Function(AppException error) failure,
  }) =>
      switch (this) {
        Ok<T>(:final data) => ok(data),
        Failure<T>(:final error) => failure(error),
      };
}

/// 成功结果。
class Ok<T> extends Result<T> {
  const Ok(this.data);

  /// 携带的数据。
  final T data;

  @override
  String toString() => 'Ok($data)';
}

/// 失败结果。
class Failure<T> extends Result<T> {
  const Failure(this.error);

  /// 失败原因。
  final AppException error;

  @override
  String toString() => 'Failure($error)';
}
