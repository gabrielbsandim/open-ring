import 'package:meta/meta.dart';

sealed class ParseResult<T> {
  const new();
}

@immutable
final class Parsed<T> extends ParseResult<T> {
  const new(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Parsed<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
final class ParseFailure<T> extends ParseResult<T> {
  const new(this.error);

  final ParseError error;

  @override
  bool operator ==(Object other) =>
      other is ParseFailure<T> && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

@immutable
sealed class ParseError {
  const new();
}

final class WrongLength extends ParseError {
  const new({required this.expected, required this.actual});

  final int expected;
  final int actual;

  @override
  bool operator ==(Object other) =>
      other is WrongLength &&
      other.expected == expected &&
      other.actual == actual;

  @override
  int get hashCode => Object.hash(expected, actual);
}

final class ByteOutOfRange extends ParseError {
  const new({required this.index, required this.value});

  final int index;
  final int value;

  @override
  bool operator ==(Object other) =>
      other is ByteOutOfRange && other.index == index && other.value == value;

  @override
  int get hashCode => Object.hash(index, value);
}

final class ChecksumMismatch extends ParseError {
  const new({required this.expected, required this.actual});

  final int expected;
  final int actual;

  @override
  bool operator ==(Object other) =>
      other is ChecksumMismatch &&
      other.expected == expected &&
      other.actual == actual;

  @override
  int get hashCode => Object.hash(expected, actual);
}

final class UnexpectedCommand extends ParseError {
  const new({required this.expected, required this.actual});

  final int expected;
  final int actual;

  @override
  bool operator ==(Object other) =>
      other is UnexpectedCommand &&
      other.expected == expected &&
      other.actual == actual;

  @override
  int get hashCode => Object.hash(expected, actual);
}

final class ErrorResponse extends ParseError {
  const new(this.command);

  final int command;

  @override
  bool operator ==(Object other) =>
      other is ErrorResponse && other.command == command;

  @override
  int get hashCode => command.hashCode;
}
