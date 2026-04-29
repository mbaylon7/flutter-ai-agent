sealed class Result<T, E> {
  const Result();
  const factory Result.ok(T value) = Ok<T, E>;
  const factory Result.err(E error) = Err<T, E>;

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  Result<U, E> map<U>(U Function(T) f) => switch (this) {
        Ok(value: final v) => Result<U, E>.ok(f(v)),
        Err(error: final e) => Result<U, E>.err(e),
      };

  R whenOr<R>({required R Function(T) ok, required R fallback}) =>
      switch (this) {
        Ok(value: final v) => ok(v),
        Err() => fallback,
      };
}

final class Ok<T, E> extends Result<T, E> {
  final T value;
  const Ok(this.value);
}

final class Err<T, E> extends Result<T, E> {
  final E error;
  const Err(this.error);
}
