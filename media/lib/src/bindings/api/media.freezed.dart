// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThumbnailSizeType {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailSizeType);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ThumbnailSizeType()';
}


}

/// @nodoc
class $ThumbnailSizeTypeCopyWith<$Res>  {
$ThumbnailSizeTypeCopyWith(ThumbnailSizeType _, $Res Function(ThumbnailSizeType) __);
}


/// Adds pattern-matching-related methods to [ThumbnailSizeType].
extension ThumbnailSizeTypePatterns on ThumbnailSizeType {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThumbnailSizeType_Icon value)?  icon,TResult Function( ThumbnailSizeType_Small value)?  small,TResult Function( ThumbnailSizeType_Medium value)?  medium,TResult Function( ThumbnailSizeType_Large value)?  large,TResult Function( ThumbnailSizeType_Larger value)?  larger,TResult Function( ThumbnailSizeType_Custom value)?  custom,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThumbnailSizeType_Icon() when icon != null:
return icon(_that);case ThumbnailSizeType_Small() when small != null:
return small(_that);case ThumbnailSizeType_Medium() when medium != null:
return medium(_that);case ThumbnailSizeType_Large() when large != null:
return large(_that);case ThumbnailSizeType_Larger() when larger != null:
return larger(_that);case ThumbnailSizeType_Custom() when custom != null:
return custom(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThumbnailSizeType_Icon value)  icon,required TResult Function( ThumbnailSizeType_Small value)  small,required TResult Function( ThumbnailSizeType_Medium value)  medium,required TResult Function( ThumbnailSizeType_Large value)  large,required TResult Function( ThumbnailSizeType_Larger value)  larger,required TResult Function( ThumbnailSizeType_Custom value)  custom,}){
final _that = this;
switch (_that) {
case ThumbnailSizeType_Icon():
return icon(_that);case ThumbnailSizeType_Small():
return small(_that);case ThumbnailSizeType_Medium():
return medium(_that);case ThumbnailSizeType_Large():
return large(_that);case ThumbnailSizeType_Larger():
return larger(_that);case ThumbnailSizeType_Custom():
return custom(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThumbnailSizeType_Icon value)?  icon,TResult? Function( ThumbnailSizeType_Small value)?  small,TResult? Function( ThumbnailSizeType_Medium value)?  medium,TResult? Function( ThumbnailSizeType_Large value)?  large,TResult? Function( ThumbnailSizeType_Larger value)?  larger,TResult? Function( ThumbnailSizeType_Custom value)?  custom,}){
final _that = this;
switch (_that) {
case ThumbnailSizeType_Icon() when icon != null:
return icon(_that);case ThumbnailSizeType_Small() when small != null:
return small(_that);case ThumbnailSizeType_Medium() when medium != null:
return medium(_that);case ThumbnailSizeType_Large() when large != null:
return large(_that);case ThumbnailSizeType_Larger() when larger != null:
return larger(_that);case ThumbnailSizeType_Custom() when custom != null:
return custom(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  icon,TResult Function()?  small,TResult Function()?  medium,TResult Function()?  large,TResult Function()?  larger,TResult Function( (int, int) field0)?  custom,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThumbnailSizeType_Icon() when icon != null:
return icon();case ThumbnailSizeType_Small() when small != null:
return small();case ThumbnailSizeType_Medium() when medium != null:
return medium();case ThumbnailSizeType_Large() when large != null:
return large();case ThumbnailSizeType_Larger() when larger != null:
return larger();case ThumbnailSizeType_Custom() when custom != null:
return custom(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  icon,required TResult Function()  small,required TResult Function()  medium,required TResult Function()  large,required TResult Function()  larger,required TResult Function( (int, int) field0)  custom,}) {final _that = this;
switch (_that) {
case ThumbnailSizeType_Icon():
return icon();case ThumbnailSizeType_Small():
return small();case ThumbnailSizeType_Medium():
return medium();case ThumbnailSizeType_Large():
return large();case ThumbnailSizeType_Larger():
return larger();case ThumbnailSizeType_Custom():
return custom(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  icon,TResult? Function()?  small,TResult? Function()?  medium,TResult? Function()?  large,TResult? Function()?  larger,TResult? Function( (int, int) field0)?  custom,}) {final _that = this;
switch (_that) {
case ThumbnailSizeType_Icon() when icon != null:
return icon();case ThumbnailSizeType_Small() when small != null:
return small();case ThumbnailSizeType_Medium() when medium != null:
return medium();case ThumbnailSizeType_Large() when large != null:
return large();case ThumbnailSizeType_Larger() when larger != null:
return larger();case ThumbnailSizeType_Custom() when custom != null:
return custom(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ThumbnailSizeType_Icon extends ThumbnailSizeType {
  const ThumbnailSizeType_Icon(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailSizeType_Icon);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ThumbnailSizeType.icon()';
}


}




/// @nodoc


class ThumbnailSizeType_Small extends ThumbnailSizeType {
  const ThumbnailSizeType_Small(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailSizeType_Small);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ThumbnailSizeType.small()';
}


}




/// @nodoc


class ThumbnailSizeType_Medium extends ThumbnailSizeType {
  const ThumbnailSizeType_Medium(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailSizeType_Medium);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ThumbnailSizeType.medium()';
}


}




/// @nodoc


class ThumbnailSizeType_Large extends ThumbnailSizeType {
  const ThumbnailSizeType_Large(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailSizeType_Large);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ThumbnailSizeType.large()';
}


}




/// @nodoc


class ThumbnailSizeType_Larger extends ThumbnailSizeType {
  const ThumbnailSizeType_Larger(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailSizeType_Larger);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ThumbnailSizeType.larger()';
}


}




/// @nodoc


class ThumbnailSizeType_Custom extends ThumbnailSizeType {
  const ThumbnailSizeType_Custom(this.field0): super._();
  

 final  (int, int) field0;

/// Create a copy of ThumbnailSizeType
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThumbnailSizeType_CustomCopyWith<ThumbnailSizeType_Custom> get copyWith => _$ThumbnailSizeType_CustomCopyWithImpl<ThumbnailSizeType_Custom>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThumbnailSizeType_Custom&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ThumbnailSizeType.custom(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ThumbnailSizeType_CustomCopyWith<$Res> implements $ThumbnailSizeTypeCopyWith<$Res> {
  factory $ThumbnailSizeType_CustomCopyWith(ThumbnailSizeType_Custom value, $Res Function(ThumbnailSizeType_Custom) _then) = _$ThumbnailSizeType_CustomCopyWithImpl;
@useResult
$Res call({
 (int, int) field0
});




}
/// @nodoc
class _$ThumbnailSizeType_CustomCopyWithImpl<$Res>
    implements $ThumbnailSizeType_CustomCopyWith<$Res> {
  _$ThumbnailSizeType_CustomCopyWithImpl(this._self, this._then);

  final ThumbnailSizeType_Custom _self;
  final $Res Function(ThumbnailSizeType_Custom) _then;

/// Create a copy of ThumbnailSizeType
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ThumbnailSizeType_Custom(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as (int, int),
  ));
}


}

// dart format on
