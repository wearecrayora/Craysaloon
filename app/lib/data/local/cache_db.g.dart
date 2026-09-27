// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_db.dart';

// ignore_for_file: type=lint
class $CachedServicesTable extends CachedServices
    with TableInfo<$CachedServicesTable, CachedService> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedServicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _salonIdMeta = const VerificationMeta(
    'salonId',
  );
  @override
  late final GeneratedColumn<String> salonId = GeneratedColumn<String>(
    'salon_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pricePaiseMeta = const VerificationMeta(
    'pricePaise',
  );
  @override
  late final GeneratedColumn<int> pricePaise = GeneratedColumn<int>(
    'price_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMinutesMeta = const VerificationMeta(
    'durationMinutes',
  );
  @override
  late final GeneratedColumn<int> durationMinutes = GeneratedColumn<int>(
    'duration_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    salonId,
    name,
    pricePaise,
    durationMinutes,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_services';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedService> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('salon_id')) {
      context.handle(
        _salonIdMeta,
        salonId.isAcceptableOrUnknown(data['salon_id']!, _salonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_salonIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_paise')) {
      context.handle(
        _pricePaiseMeta,
        pricePaise.isAcceptableOrUnknown(data['price_paise']!, _pricePaiseMeta),
      );
    } else if (isInserting) {
      context.missing(_pricePaiseMeta);
    }
    if (data.containsKey('duration_minutes')) {
      context.handle(
        _durationMinutesMeta,
        durationMinutes.isAcceptableOrUnknown(
          data['duration_minutes']!,
          _durationMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationMinutesMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedService map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedService(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      salonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}salon_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      pricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_paise'],
      )!,
      durationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_minutes'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $CachedServicesTable createAlias(String alias) {
    return $CachedServicesTable(attachedDatabase, alias);
  }
}

class CachedService extends DataClass implements Insertable<CachedService> {
  final String id;
  final String salonId;
  final String name;
  final int pricePaise;
  final int durationMinutes;
  final bool active;
  const CachedService({
    required this.id,
    required this.salonId,
    required this.name,
    required this.pricePaise,
    required this.durationMinutes,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['salon_id'] = Variable<String>(salonId);
    map['name'] = Variable<String>(name);
    map['price_paise'] = Variable<int>(pricePaise);
    map['duration_minutes'] = Variable<int>(durationMinutes);
    map['active'] = Variable<bool>(active);
    return map;
  }

  CachedServicesCompanion toCompanion(bool nullToAbsent) {
    return CachedServicesCompanion(
      id: Value(id),
      salonId: Value(salonId),
      name: Value(name),
      pricePaise: Value(pricePaise),
      durationMinutes: Value(durationMinutes),
      active: Value(active),
    );
  }

  factory CachedService.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedService(
      id: serializer.fromJson<String>(json['id']),
      salonId: serializer.fromJson<String>(json['salonId']),
      name: serializer.fromJson<String>(json['name']),
      pricePaise: serializer.fromJson<int>(json['pricePaise']),
      durationMinutes: serializer.fromJson<int>(json['durationMinutes']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'salonId': serializer.toJson<String>(salonId),
      'name': serializer.toJson<String>(name),
      'pricePaise': serializer.toJson<int>(pricePaise),
      'durationMinutes': serializer.toJson<int>(durationMinutes),
      'active': serializer.toJson<bool>(active),
    };
  }

  CachedService copyWith({
    String? id,
    String? salonId,
    String? name,
    int? pricePaise,
    int? durationMinutes,
    bool? active,
  }) => CachedService(
    id: id ?? this.id,
    salonId: salonId ?? this.salonId,
    name: name ?? this.name,
    pricePaise: pricePaise ?? this.pricePaise,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    active: active ?? this.active,
  );
  CachedService copyWithCompanion(CachedServicesCompanion data) {
    return CachedService(
      id: data.id.present ? data.id.value : this.id,
      salonId: data.salonId.present ? data.salonId.value : this.salonId,
      name: data.name.present ? data.name.value : this.name,
      pricePaise: data.pricePaise.present
          ? data.pricePaise.value
          : this.pricePaise,
      durationMinutes: data.durationMinutes.present
          ? data.durationMinutes.value
          : this.durationMinutes,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedService(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('pricePaise: $pricePaise, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, salonId, name, pricePaise, durationMinutes, active);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedService &&
          other.id == this.id &&
          other.salonId == this.salonId &&
          other.name == this.name &&
          other.pricePaise == this.pricePaise &&
          other.durationMinutes == this.durationMinutes &&
          other.active == this.active);
}

class CachedServicesCompanion extends UpdateCompanion<CachedService> {
  final Value<String> id;
  final Value<String> salonId;
  final Value<String> name;
  final Value<int> pricePaise;
  final Value<int> durationMinutes;
  final Value<bool> active;
  final Value<int> rowid;
  const CachedServicesCompanion({
    this.id = const Value.absent(),
    this.salonId = const Value.absent(),
    this.name = const Value.absent(),
    this.pricePaise = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedServicesCompanion.insert({
    required String id,
    required String salonId,
    required String name,
    required int pricePaise,
    required int durationMinutes,
    required bool active,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       salonId = Value(salonId),
       name = Value(name),
       pricePaise = Value(pricePaise),
       durationMinutes = Value(durationMinutes),
       active = Value(active);
  static Insertable<CachedService> custom({
    Expression<String>? id,
    Expression<String>? salonId,
    Expression<String>? name,
    Expression<int>? pricePaise,
    Expression<int>? durationMinutes,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (salonId != null) 'salon_id': salonId,
      if (name != null) 'name': name,
      if (pricePaise != null) 'price_paise': pricePaise,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedServicesCompanion copyWith({
    Value<String>? id,
    Value<String>? salonId,
    Value<String>? name,
    Value<int>? pricePaise,
    Value<int>? durationMinutes,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return CachedServicesCompanion(
      id: id ?? this.id,
      salonId: salonId ?? this.salonId,
      name: name ?? this.name,
      pricePaise: pricePaise ?? this.pricePaise,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (salonId.present) {
      map['salon_id'] = Variable<String>(salonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (pricePaise.present) {
      map['price_paise'] = Variable<int>(pricePaise.value);
    }
    if (durationMinutes.present) {
      map['duration_minutes'] = Variable<int>(durationMinutes.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedServicesCompanion(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('pricePaise: $pricePaise, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedAddOnsTable extends CachedAddOns
    with TableInfo<$CachedAddOnsTable, CachedAddOn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedAddOnsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _salonIdMeta = const VerificationMeta(
    'salonId',
  );
  @override
  late final GeneratedColumn<String> salonId = GeneratedColumn<String>(
    'salon_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pricePaiseMeta = const VerificationMeta(
    'pricePaise',
  );
  @override
  late final GeneratedColumn<int> pricePaise = GeneratedColumn<int>(
    'price_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extraDurationMinutesMeta =
      const VerificationMeta('extraDurationMinutes');
  @override
  late final GeneratedColumn<int> extraDurationMinutes = GeneratedColumn<int>(
    'extra_duration_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    salonId,
    name,
    pricePaise,
    extraDurationMinutes,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_add_ons';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedAddOn> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('salon_id')) {
      context.handle(
        _salonIdMeta,
        salonId.isAcceptableOrUnknown(data['salon_id']!, _salonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_salonIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_paise')) {
      context.handle(
        _pricePaiseMeta,
        pricePaise.isAcceptableOrUnknown(data['price_paise']!, _pricePaiseMeta),
      );
    } else if (isInserting) {
      context.missing(_pricePaiseMeta);
    }
    if (data.containsKey('extra_duration_minutes')) {
      context.handle(
        _extraDurationMinutesMeta,
        extraDurationMinutes.isAcceptableOrUnknown(
          data['extra_duration_minutes']!,
          _extraDurationMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_extraDurationMinutesMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedAddOn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedAddOn(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      salonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}salon_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      pricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_paise'],
      )!,
      extraDurationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}extra_duration_minutes'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $CachedAddOnsTable createAlias(String alias) {
    return $CachedAddOnsTable(attachedDatabase, alias);
  }
}

class CachedAddOn extends DataClass implements Insertable<CachedAddOn> {
  final String id;
  final String salonId;
  final String name;
  final int pricePaise;
  final int extraDurationMinutes;
  final bool active;
  const CachedAddOn({
    required this.id,
    required this.salonId,
    required this.name,
    required this.pricePaise,
    required this.extraDurationMinutes,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['salon_id'] = Variable<String>(salonId);
    map['name'] = Variable<String>(name);
    map['price_paise'] = Variable<int>(pricePaise);
    map['extra_duration_minutes'] = Variable<int>(extraDurationMinutes);
    map['active'] = Variable<bool>(active);
    return map;
  }

  CachedAddOnsCompanion toCompanion(bool nullToAbsent) {
    return CachedAddOnsCompanion(
      id: Value(id),
      salonId: Value(salonId),
      name: Value(name),
      pricePaise: Value(pricePaise),
      extraDurationMinutes: Value(extraDurationMinutes),
      active: Value(active),
    );
  }

  factory CachedAddOn.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedAddOn(
      id: serializer.fromJson<String>(json['id']),
      salonId: serializer.fromJson<String>(json['salonId']),
      name: serializer.fromJson<String>(json['name']),
      pricePaise: serializer.fromJson<int>(json['pricePaise']),
      extraDurationMinutes: serializer.fromJson<int>(
        json['extraDurationMinutes'],
      ),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'salonId': serializer.toJson<String>(salonId),
      'name': serializer.toJson<String>(name),
      'pricePaise': serializer.toJson<int>(pricePaise),
      'extraDurationMinutes': serializer.toJson<int>(extraDurationMinutes),
      'active': serializer.toJson<bool>(active),
    };
  }

  CachedAddOn copyWith({
    String? id,
    String? salonId,
    String? name,
    int? pricePaise,
    int? extraDurationMinutes,
    bool? active,
  }) => CachedAddOn(
    id: id ?? this.id,
    salonId: salonId ?? this.salonId,
    name: name ?? this.name,
    pricePaise: pricePaise ?? this.pricePaise,
    extraDurationMinutes: extraDurationMinutes ?? this.extraDurationMinutes,
    active: active ?? this.active,
  );
  CachedAddOn copyWithCompanion(CachedAddOnsCompanion data) {
    return CachedAddOn(
      id: data.id.present ? data.id.value : this.id,
      salonId: data.salonId.present ? data.salonId.value : this.salonId,
      name: data.name.present ? data.name.value : this.name,
      pricePaise: data.pricePaise.present
          ? data.pricePaise.value
          : this.pricePaise,
      extraDurationMinutes: data.extraDurationMinutes.present
          ? data.extraDurationMinutes.value
          : this.extraDurationMinutes,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedAddOn(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('pricePaise: $pricePaise, ')
          ..write('extraDurationMinutes: $extraDurationMinutes, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, salonId, name, pricePaise, extraDurationMinutes, active);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedAddOn &&
          other.id == this.id &&
          other.salonId == this.salonId &&
          other.name == this.name &&
          other.pricePaise == this.pricePaise &&
          other.extraDurationMinutes == this.extraDurationMinutes &&
          other.active == this.active);
}

class CachedAddOnsCompanion extends UpdateCompanion<CachedAddOn> {
  final Value<String> id;
  final Value<String> salonId;
  final Value<String> name;
  final Value<int> pricePaise;
  final Value<int> extraDurationMinutes;
  final Value<bool> active;
  final Value<int> rowid;
  const CachedAddOnsCompanion({
    this.id = const Value.absent(),
    this.salonId = const Value.absent(),
    this.name = const Value.absent(),
    this.pricePaise = const Value.absent(),
    this.extraDurationMinutes = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedAddOnsCompanion.insert({
    required String id,
    required String salonId,
    required String name,
    required int pricePaise,
    required int extraDurationMinutes,
    required bool active,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       salonId = Value(salonId),
       name = Value(name),
       pricePaise = Value(pricePaise),
       extraDurationMinutes = Value(extraDurationMinutes),
       active = Value(active);
  static Insertable<CachedAddOn> custom({
    Expression<String>? id,
    Expression<String>? salonId,
    Expression<String>? name,
    Expression<int>? pricePaise,
    Expression<int>? extraDurationMinutes,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (salonId != null) 'salon_id': salonId,
      if (name != null) 'name': name,
      if (pricePaise != null) 'price_paise': pricePaise,
      if (extraDurationMinutes != null)
        'extra_duration_minutes': extraDurationMinutes,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedAddOnsCompanion copyWith({
    Value<String>? id,
    Value<String>? salonId,
    Value<String>? name,
    Value<int>? pricePaise,
    Value<int>? extraDurationMinutes,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return CachedAddOnsCompanion(
      id: id ?? this.id,
      salonId: salonId ?? this.salonId,
      name: name ?? this.name,
      pricePaise: pricePaise ?? this.pricePaise,
      extraDurationMinutes: extraDurationMinutes ?? this.extraDurationMinutes,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (salonId.present) {
      map['salon_id'] = Variable<String>(salonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (pricePaise.present) {
      map['price_paise'] = Variable<int>(pricePaise.value);
    }
    if (extraDurationMinutes.present) {
      map['extra_duration_minutes'] = Variable<int>(extraDurationMinutes.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedAddOnsCompanion(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('pricePaise: $pricePaise, ')
          ..write('extraDurationMinutes: $extraDurationMinutes, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedStaffMembersTable extends CachedStaffMembers
    with TableInfo<$CachedStaffMembersTable, CachedStaff> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedStaffMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _salonIdMeta = const VerificationMeta(
    'salonId',
  );
  @override
  late final GeneratedColumn<String> salonId = GeneratedColumn<String>(
    'salon_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, salonId, name, active];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_staff_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedStaff> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('salon_id')) {
      context.handle(
        _salonIdMeta,
        salonId.isAcceptableOrUnknown(data['salon_id']!, _salonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_salonIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedStaff map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedStaff(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      salonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}salon_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $CachedStaffMembersTable createAlias(String alias) {
    return $CachedStaffMembersTable(attachedDatabase, alias);
  }
}

class CachedStaff extends DataClass implements Insertable<CachedStaff> {
  final String id;
  final String salonId;
  final String name;
  final bool active;
  const CachedStaff({
    required this.id,
    required this.salonId,
    required this.name,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['salon_id'] = Variable<String>(salonId);
    map['name'] = Variable<String>(name);
    map['active'] = Variable<bool>(active);
    return map;
  }

  CachedStaffMembersCompanion toCompanion(bool nullToAbsent) {
    return CachedStaffMembersCompanion(
      id: Value(id),
      salonId: Value(salonId),
      name: Value(name),
      active: Value(active),
    );
  }

  factory CachedStaff.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedStaff(
      id: serializer.fromJson<String>(json['id']),
      salonId: serializer.fromJson<String>(json['salonId']),
      name: serializer.fromJson<String>(json['name']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'salonId': serializer.toJson<String>(salonId),
      'name': serializer.toJson<String>(name),
      'active': serializer.toJson<bool>(active),
    };
  }

  CachedStaff copyWith({
    String? id,
    String? salonId,
    String? name,
    bool? active,
  }) => CachedStaff(
    id: id ?? this.id,
    salonId: salonId ?? this.salonId,
    name: name ?? this.name,
    active: active ?? this.active,
  );
  CachedStaff copyWithCompanion(CachedStaffMembersCompanion data) {
    return CachedStaff(
      id: data.id.present ? data.id.value : this.id,
      salonId: data.salonId.present ? data.salonId.value : this.salonId,
      name: data.name.present ? data.name.value : this.name,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedStaff(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, salonId, name, active);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedStaff &&
          other.id == this.id &&
          other.salonId == this.salonId &&
          other.name == this.name &&
          other.active == this.active);
}

class CachedStaffMembersCompanion extends UpdateCompanion<CachedStaff> {
  final Value<String> id;
  final Value<String> salonId;
  final Value<String> name;
  final Value<bool> active;
  final Value<int> rowid;
  const CachedStaffMembersCompanion({
    this.id = const Value.absent(),
    this.salonId = const Value.absent(),
    this.name = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedStaffMembersCompanion.insert({
    required String id,
    required String salonId,
    required String name,
    required bool active,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       salonId = Value(salonId),
       name = Value(name),
       active = Value(active);
  static Insertable<CachedStaff> custom({
    Expression<String>? id,
    Expression<String>? salonId,
    Expression<String>? name,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (salonId != null) 'salon_id': salonId,
      if (name != null) 'name': name,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedStaffMembersCompanion copyWith({
    Value<String>? id,
    Value<String>? salonId,
    Value<String>? name,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return CachedStaffMembersCompanion(
      id: id ?? this.id,
      salonId: salonId ?? this.salonId,
      name: name ?? this.name,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (salonId.present) {
      map['salon_id'] = Variable<String>(salonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedStaffMembersCompanion(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCustomersTable extends CachedCustomers
    with TableInfo<$CachedCustomersTable, CachedCustomer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _salonIdMeta = const VerificationMeta(
    'salonId',
  );
  @override
  late final GeneratedColumn<String> salonId = GeneratedColumn<String>(
    'salon_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastVisitAtMeta = const VerificationMeta(
    'lastVisitAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastVisitAt = GeneratedColumn<DateTime>(
    'last_visit_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _balancePaiseMeta = const VerificationMeta(
    'balancePaise',
  );
  @override
  late final GeneratedColumn<int> balancePaise = GeneratedColumn<int>(
    'balance_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _visitCountMeta = const VerificationMeta(
    'visitCount',
  );
  @override
  late final GeneratedColumn<int> visitCount = GeneratedColumn<int>(
    'visit_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    salonId,
    name,
    phone,
    lastVisitAt,
    balancePaise,
    visitCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCustomer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('salon_id')) {
      context.handle(
        _salonIdMeta,
        salonId.isAcceptableOrUnknown(data['salon_id']!, _salonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_salonIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('last_visit_at')) {
      context.handle(
        _lastVisitAtMeta,
        lastVisitAt.isAcceptableOrUnknown(
          data['last_visit_at']!,
          _lastVisitAtMeta,
        ),
      );
    }
    if (data.containsKey('balance_paise')) {
      context.handle(
        _balancePaiseMeta,
        balancePaise.isAcceptableOrUnknown(
          data['balance_paise']!,
          _balancePaiseMeta,
        ),
      );
    }
    if (data.containsKey('visit_count')) {
      context.handle(
        _visitCountMeta,
        visitCount.isAcceptableOrUnknown(data['visit_count']!, _visitCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedCustomer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCustomer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      salonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}salon_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      lastVisitAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_visit_at'],
      ),
      balancePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_paise'],
      )!,
      visitCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}visit_count'],
      )!,
    );
  }

  @override
  $CachedCustomersTable createAlias(String alias) {
    return $CachedCustomersTable(attachedDatabase, alias);
  }
}

class CachedCustomer extends DataClass implements Insertable<CachedCustomer> {
  final String id;
  final String salonId;
  final String? name;
  final String? phone;
  final DateTime? lastVisitAt;
  final int balancePaise;
  final int visitCount;
  const CachedCustomer({
    required this.id,
    required this.salonId,
    this.name,
    this.phone,
    this.lastVisitAt,
    required this.balancePaise,
    required this.visitCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['salon_id'] = Variable<String>(salonId);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || lastVisitAt != null) {
      map['last_visit_at'] = Variable<DateTime>(lastVisitAt);
    }
    map['balance_paise'] = Variable<int>(balancePaise);
    map['visit_count'] = Variable<int>(visitCount);
    return map;
  }

  CachedCustomersCompanion toCompanion(bool nullToAbsent) {
    return CachedCustomersCompanion(
      id: Value(id),
      salonId: Value(salonId),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      lastVisitAt: lastVisitAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVisitAt),
      balancePaise: Value(balancePaise),
      visitCount: Value(visitCount),
    );
  }

  factory CachedCustomer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCustomer(
      id: serializer.fromJson<String>(json['id']),
      salonId: serializer.fromJson<String>(json['salonId']),
      name: serializer.fromJson<String?>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      lastVisitAt: serializer.fromJson<DateTime?>(json['lastVisitAt']),
      balancePaise: serializer.fromJson<int>(json['balancePaise']),
      visitCount: serializer.fromJson<int>(json['visitCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'salonId': serializer.toJson<String>(salonId),
      'name': serializer.toJson<String?>(name),
      'phone': serializer.toJson<String?>(phone),
      'lastVisitAt': serializer.toJson<DateTime?>(lastVisitAt),
      'balancePaise': serializer.toJson<int>(balancePaise),
      'visitCount': serializer.toJson<int>(visitCount),
    };
  }

  CachedCustomer copyWith({
    String? id,
    String? salonId,
    Value<String?> name = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<DateTime?> lastVisitAt = const Value.absent(),
    int? balancePaise,
    int? visitCount,
  }) => CachedCustomer(
    id: id ?? this.id,
    salonId: salonId ?? this.salonId,
    name: name.present ? name.value : this.name,
    phone: phone.present ? phone.value : this.phone,
    lastVisitAt: lastVisitAt.present ? lastVisitAt.value : this.lastVisitAt,
    balancePaise: balancePaise ?? this.balancePaise,
    visitCount: visitCount ?? this.visitCount,
  );
  CachedCustomer copyWithCompanion(CachedCustomersCompanion data) {
    return CachedCustomer(
      id: data.id.present ? data.id.value : this.id,
      salonId: data.salonId.present ? data.salonId.value : this.salonId,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      lastVisitAt: data.lastVisitAt.present
          ? data.lastVisitAt.value
          : this.lastVisitAt,
      balancePaise: data.balancePaise.present
          ? data.balancePaise.value
          : this.balancePaise,
      visitCount: data.visitCount.present
          ? data.visitCount.value
          : this.visitCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomer(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('lastVisitAt: $lastVisitAt, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('visitCount: $visitCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    salonId,
    name,
    phone,
    lastVisitAt,
    balancePaise,
    visitCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCustomer &&
          other.id == this.id &&
          other.salonId == this.salonId &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.lastVisitAt == this.lastVisitAt &&
          other.balancePaise == this.balancePaise &&
          other.visitCount == this.visitCount);
}

class CachedCustomersCompanion extends UpdateCompanion<CachedCustomer> {
  final Value<String> id;
  final Value<String> salonId;
  final Value<String?> name;
  final Value<String?> phone;
  final Value<DateTime?> lastVisitAt;
  final Value<int> balancePaise;
  final Value<int> visitCount;
  final Value<int> rowid;
  const CachedCustomersCompanion({
    this.id = const Value.absent(),
    this.salonId = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.lastVisitAt = const Value.absent(),
    this.balancePaise = const Value.absent(),
    this.visitCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCustomersCompanion.insert({
    required String id,
    required String salonId,
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.lastVisitAt = const Value.absent(),
    this.balancePaise = const Value.absent(),
    this.visitCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       salonId = Value(salonId);
  static Insertable<CachedCustomer> custom({
    Expression<String>? id,
    Expression<String>? salonId,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<DateTime>? lastVisitAt,
    Expression<int>? balancePaise,
    Expression<int>? visitCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (salonId != null) 'salon_id': salonId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (lastVisitAt != null) 'last_visit_at': lastVisitAt,
      if (balancePaise != null) 'balance_paise': balancePaise,
      if (visitCount != null) 'visit_count': visitCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCustomersCompanion copyWith({
    Value<String>? id,
    Value<String>? salonId,
    Value<String?>? name,
    Value<String?>? phone,
    Value<DateTime?>? lastVisitAt,
    Value<int>? balancePaise,
    Value<int>? visitCount,
    Value<int>? rowid,
  }) {
    return CachedCustomersCompanion(
      id: id ?? this.id,
      salonId: salonId ?? this.salonId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      lastVisitAt: lastVisitAt ?? this.lastVisitAt,
      balancePaise: balancePaise ?? this.balancePaise,
      visitCount: visitCount ?? this.visitCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (salonId.present) {
      map['salon_id'] = Variable<String>(salonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (lastVisitAt.present) {
      map['last_visit_at'] = Variable<DateTime>(lastVisitAt.value);
    }
    if (balancePaise.present) {
      map['balance_paise'] = Variable<int>(balancePaise.value);
    }
    if (visitCount.present) {
      map['visit_count'] = Variable<int>(visitCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomersCompanion(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('lastVisitAt: $lastVisitAt, ')
          ..write('balancePaise: $balancePaise, ')
          ..write('visitCount: $visitCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedVisitsTable extends CachedVisits
    with TableInfo<$CachedVisitsTable, CachedVisit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedVisitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _salonIdMeta = const VerificationMeta(
    'salonId',
  );
  @override
  late final GeneratedColumn<String> salonId = GeneratedColumn<String>(
    'salon_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finalAmountPaiseMeta = const VerificationMeta(
    'finalAmountPaise',
  );
  @override
  late final GeneratedColumn<int> finalAmountPaise = GeneratedColumn<int>(
    'final_amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serviceNamesMeta = const VerificationMeta(
    'serviceNames',
  );
  @override
  late final GeneratedColumn<String> serviceNames = GeneratedColumn<String>(
    'service_names',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    salonId,
    customerId,
    completedAt,
    finalAmountPaise,
    serviceNames,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_visits';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedVisit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('salon_id')) {
      context.handle(
        _salonIdMeta,
        salonId.isAcceptableOrUnknown(data['salon_id']!, _salonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_salonIdMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completedAtMeta);
    }
    if (data.containsKey('final_amount_paise')) {
      context.handle(
        _finalAmountPaiseMeta,
        finalAmountPaise.isAcceptableOrUnknown(
          data['final_amount_paise']!,
          _finalAmountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_finalAmountPaiseMeta);
    }
    if (data.containsKey('service_names')) {
      context.handle(
        _serviceNamesMeta,
        serviceNames.isAcceptableOrUnknown(
          data['service_names']!,
          _serviceNamesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedVisit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedVisit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      salonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}salon_id'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      )!,
      finalAmountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}final_amount_paise'],
      )!,
      serviceNames: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_names'],
      )!,
    );
  }

  @override
  $CachedVisitsTable createAlias(String alias) {
    return $CachedVisitsTable(attachedDatabase, alias);
  }
}

class CachedVisit extends DataClass implements Insertable<CachedVisit> {
  final String id;
  final String salonId;
  final String customerId;
  final DateTime completedAt;
  final int finalAmountPaise;
  final String serviceNames;
  const CachedVisit({
    required this.id,
    required this.salonId,
    required this.customerId,
    required this.completedAt,
    required this.finalAmountPaise,
    required this.serviceNames,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['salon_id'] = Variable<String>(salonId);
    map['customer_id'] = Variable<String>(customerId);
    map['completed_at'] = Variable<DateTime>(completedAt);
    map['final_amount_paise'] = Variable<int>(finalAmountPaise);
    map['service_names'] = Variable<String>(serviceNames);
    return map;
  }

  CachedVisitsCompanion toCompanion(bool nullToAbsent) {
    return CachedVisitsCompanion(
      id: Value(id),
      salonId: Value(salonId),
      customerId: Value(customerId),
      completedAt: Value(completedAt),
      finalAmountPaise: Value(finalAmountPaise),
      serviceNames: Value(serviceNames),
    );
  }

  factory CachedVisit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedVisit(
      id: serializer.fromJson<String>(json['id']),
      salonId: serializer.fromJson<String>(json['salonId']),
      customerId: serializer.fromJson<String>(json['customerId']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
      finalAmountPaise: serializer.fromJson<int>(json['finalAmountPaise']),
      serviceNames: serializer.fromJson<String>(json['serviceNames']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'salonId': serializer.toJson<String>(salonId),
      'customerId': serializer.toJson<String>(customerId),
      'completedAt': serializer.toJson<DateTime>(completedAt),
      'finalAmountPaise': serializer.toJson<int>(finalAmountPaise),
      'serviceNames': serializer.toJson<String>(serviceNames),
    };
  }

  CachedVisit copyWith({
    String? id,
    String? salonId,
    String? customerId,
    DateTime? completedAt,
    int? finalAmountPaise,
    String? serviceNames,
  }) => CachedVisit(
    id: id ?? this.id,
    salonId: salonId ?? this.salonId,
    customerId: customerId ?? this.customerId,
    completedAt: completedAt ?? this.completedAt,
    finalAmountPaise: finalAmountPaise ?? this.finalAmountPaise,
    serviceNames: serviceNames ?? this.serviceNames,
  );
  CachedVisit copyWithCompanion(CachedVisitsCompanion data) {
    return CachedVisit(
      id: data.id.present ? data.id.value : this.id,
      salonId: data.salonId.present ? data.salonId.value : this.salonId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      finalAmountPaise: data.finalAmountPaise.present
          ? data.finalAmountPaise.value
          : this.finalAmountPaise,
      serviceNames: data.serviceNames.present
          ? data.serviceNames.value
          : this.serviceNames,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedVisit(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('customerId: $customerId, ')
          ..write('completedAt: $completedAt, ')
          ..write('finalAmountPaise: $finalAmountPaise, ')
          ..write('serviceNames: $serviceNames')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    salonId,
    customerId,
    completedAt,
    finalAmountPaise,
    serviceNames,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedVisit &&
          other.id == this.id &&
          other.salonId == this.salonId &&
          other.customerId == this.customerId &&
          other.completedAt == this.completedAt &&
          other.finalAmountPaise == this.finalAmountPaise &&
          other.serviceNames == this.serviceNames);
}

class CachedVisitsCompanion extends UpdateCompanion<CachedVisit> {
  final Value<String> id;
  final Value<String> salonId;
  final Value<String> customerId;
  final Value<DateTime> completedAt;
  final Value<int> finalAmountPaise;
  final Value<String> serviceNames;
  final Value<int> rowid;
  const CachedVisitsCompanion({
    this.id = const Value.absent(),
    this.salonId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.finalAmountPaise = const Value.absent(),
    this.serviceNames = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedVisitsCompanion.insert({
    required String id,
    required String salonId,
    required String customerId,
    required DateTime completedAt,
    required int finalAmountPaise,
    this.serviceNames = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       salonId = Value(salonId),
       customerId = Value(customerId),
       completedAt = Value(completedAt),
       finalAmountPaise = Value(finalAmountPaise);
  static Insertable<CachedVisit> custom({
    Expression<String>? id,
    Expression<String>? salonId,
    Expression<String>? customerId,
    Expression<DateTime>? completedAt,
    Expression<int>? finalAmountPaise,
    Expression<String>? serviceNames,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (salonId != null) 'salon_id': salonId,
      if (customerId != null) 'customer_id': customerId,
      if (completedAt != null) 'completed_at': completedAt,
      if (finalAmountPaise != null) 'final_amount_paise': finalAmountPaise,
      if (serviceNames != null) 'service_names': serviceNames,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedVisitsCompanion copyWith({
    Value<String>? id,
    Value<String>? salonId,
    Value<String>? customerId,
    Value<DateTime>? completedAt,
    Value<int>? finalAmountPaise,
    Value<String>? serviceNames,
    Value<int>? rowid,
  }) {
    return CachedVisitsCompanion(
      id: id ?? this.id,
      salonId: salonId ?? this.salonId,
      customerId: customerId ?? this.customerId,
      completedAt: completedAt ?? this.completedAt,
      finalAmountPaise: finalAmountPaise ?? this.finalAmountPaise,
      serviceNames: serviceNames ?? this.serviceNames,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (salonId.present) {
      map['salon_id'] = Variable<String>(salonId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (finalAmountPaise.present) {
      map['final_amount_paise'] = Variable<int>(finalAmountPaise.value);
    }
    if (serviceNames.present) {
      map['service_names'] = Variable<String>(serviceNames.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedVisitsCompanion(')
          ..write('id: $id, ')
          ..write('salonId: $salonId, ')
          ..write('customerId: $customerId, ')
          ..write('completedAt: $completedAt, ')
          ..write('finalAmountPaise: $finalAmountPaise, ')
          ..write('serviceNames: $serviceNames, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CacheStampsTable extends CacheStamps
    with TableInfo<$CacheStampsTable, CacheStamp> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheStampsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<DateTime> refreshedAt = GeneratedColumn<DateTime>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, refreshedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_stamps';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheStamp> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheStamp map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheStamp(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refreshed_at'],
      )!,
    );
  }

  @override
  $CacheStampsTable createAlias(String alias) {
    return $CacheStampsTable(attachedDatabase, alias);
  }
}

class CacheStamp extends DataClass implements Insertable<CacheStamp> {
  final String key;
  final DateTime refreshedAt;
  const CacheStamp({required this.key, required this.refreshedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['refreshed_at'] = Variable<DateTime>(refreshedAt);
    return map;
  }

  CacheStampsCompanion toCompanion(bool nullToAbsent) {
    return CacheStampsCompanion(
      key: Value(key),
      refreshedAt: Value(refreshedAt),
    );
  }

  factory CacheStamp.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheStamp(
      key: serializer.fromJson<String>(json['key']),
      refreshedAt: serializer.fromJson<DateTime>(json['refreshedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'refreshedAt': serializer.toJson<DateTime>(refreshedAt),
    };
  }

  CacheStamp copyWith({String? key, DateTime? refreshedAt}) => CacheStamp(
    key: key ?? this.key,
    refreshedAt: refreshedAt ?? this.refreshedAt,
  );
  CacheStamp copyWithCompanion(CacheStampsCompanion data) {
    return CacheStamp(
      key: data.key.present ? data.key.value : this.key,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheStamp(')
          ..write('key: $key, ')
          ..write('refreshedAt: $refreshedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, refreshedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheStamp &&
          other.key == this.key &&
          other.refreshedAt == this.refreshedAt);
}

class CacheStampsCompanion extends UpdateCompanion<CacheStamp> {
  final Value<String> key;
  final Value<DateTime> refreshedAt;
  final Value<int> rowid;
  const CacheStampsCompanion({
    this.key = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheStampsCompanion.insert({
    required String key,
    required DateTime refreshedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       refreshedAt = Value(refreshedAt);
  static Insertable<CacheStamp> custom({
    Expression<String>? key,
    Expression<DateTime>? refreshedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheStampsCompanion copyWith({
    Value<String>? key,
    Value<DateTime>? refreshedAt,
    Value<int>? rowid,
  }) {
    return CacheStampsCompanion(
      key: key ?? this.key,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<DateTime>(refreshedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheStampsCompanion(')
          ..write('key: $key, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDb extends GeneratedDatabase {
  _$CacheDb(QueryExecutor e) : super(e);
  $CacheDbManager get managers => $CacheDbManager(this);
  late final $CachedServicesTable cachedServices = $CachedServicesTable(this);
  late final $CachedAddOnsTable cachedAddOns = $CachedAddOnsTable(this);
  late final $CachedStaffMembersTable cachedStaffMembers =
      $CachedStaffMembersTable(this);
  late final $CachedCustomersTable cachedCustomers = $CachedCustomersTable(
    this,
  );
  late final $CachedVisitsTable cachedVisits = $CachedVisitsTable(this);
  late final $CacheStampsTable cacheStamps = $CacheStampsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedServices,
    cachedAddOns,
    cachedStaffMembers,
    cachedCustomers,
    cachedVisits,
    cacheStamps,
  ];
}

typedef $$CachedServicesTableCreateCompanionBuilder =
    CachedServicesCompanion Function({
      required String id,
      required String salonId,
      required String name,
      required int pricePaise,
      required int durationMinutes,
      required bool active,
      Value<int> rowid,
    });
typedef $$CachedServicesTableUpdateCompanionBuilder =
    CachedServicesCompanion Function({
      Value<String> id,
      Value<String> salonId,
      Value<String> name,
      Value<int> pricePaise,
      Value<int> durationMinutes,
      Value<bool> active,
      Value<int> rowid,
    });

class $$CachedServicesTableFilterComposer
    extends Composer<_$CacheDb, $CachedServicesTable> {
  $$CachedServicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedServicesTableOrderingComposer
    extends Composer<_$CacheDb, $CachedServicesTable> {
  $$CachedServicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedServicesTableAnnotationComposer
    extends Composer<_$CacheDb, $CachedServicesTable> {
  $$CachedServicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get salonId =>
      $composableBuilder(column: $table.salonId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$CachedServicesTableTableManager
    extends
        RootTableManager<
          _$CacheDb,
          $CachedServicesTable,
          CachedService,
          $$CachedServicesTableFilterComposer,
          $$CachedServicesTableOrderingComposer,
          $$CachedServicesTableAnnotationComposer,
          $$CachedServicesTableCreateCompanionBuilder,
          $$CachedServicesTableUpdateCompanionBuilder,
          (
            CachedService,
            BaseReferences<_$CacheDb, $CachedServicesTable, CachedService>,
          ),
          CachedService,
          PrefetchHooks Function()
        > {
  $$CachedServicesTableTableManager(_$CacheDb db, $CachedServicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedServicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedServicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedServicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> salonId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> pricePaise = const Value.absent(),
                Value<int> durationMinutes = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedServicesCompanion(
                id: id,
                salonId: salonId,
                name: name,
                pricePaise: pricePaise,
                durationMinutes: durationMinutes,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String salonId,
                required String name,
                required int pricePaise,
                required int durationMinutes,
                required bool active,
                Value<int> rowid = const Value.absent(),
              }) => CachedServicesCompanion.insert(
                id: id,
                salonId: salonId,
                name: name,
                pricePaise: pricePaise,
                durationMinutes: durationMinutes,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedServicesTable, CachedService>(table),
                  BaseReferences<
                    _$CacheDb,
                    $CachedServicesTable,
                    CachedService
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedServicesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDb,
      $CachedServicesTable,
      CachedService,
      $$CachedServicesTableFilterComposer,
      $$CachedServicesTableOrderingComposer,
      $$CachedServicesTableAnnotationComposer,
      $$CachedServicesTableCreateCompanionBuilder,
      $$CachedServicesTableUpdateCompanionBuilder,
      (
        CachedService,
        BaseReferences<_$CacheDb, $CachedServicesTable, CachedService>,
      ),
      CachedService,
      PrefetchHooks Function()
    >;
typedef $$CachedAddOnsTableCreateCompanionBuilder =
    CachedAddOnsCompanion Function({
      required String id,
      required String salonId,
      required String name,
      required int pricePaise,
      required int extraDurationMinutes,
      required bool active,
      Value<int> rowid,
    });
typedef $$CachedAddOnsTableUpdateCompanionBuilder =
    CachedAddOnsCompanion Function({
      Value<String> id,
      Value<String> salonId,
      Value<String> name,
      Value<int> pricePaise,
      Value<int> extraDurationMinutes,
      Value<bool> active,
      Value<int> rowid,
    });

class $$CachedAddOnsTableFilterComposer
    extends Composer<_$CacheDb, $CachedAddOnsTable> {
  $$CachedAddOnsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get extraDurationMinutes => $composableBuilder(
    column: $table.extraDurationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedAddOnsTableOrderingComposer
    extends Composer<_$CacheDb, $CachedAddOnsTable> {
  $$CachedAddOnsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get extraDurationMinutes => $composableBuilder(
    column: $table.extraDurationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedAddOnsTableAnnotationComposer
    extends Composer<_$CacheDb, $CachedAddOnsTable> {
  $$CachedAddOnsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get salonId =>
      $composableBuilder(column: $table.salonId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get extraDurationMinutes => $composableBuilder(
    column: $table.extraDurationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$CachedAddOnsTableTableManager
    extends
        RootTableManager<
          _$CacheDb,
          $CachedAddOnsTable,
          CachedAddOn,
          $$CachedAddOnsTableFilterComposer,
          $$CachedAddOnsTableOrderingComposer,
          $$CachedAddOnsTableAnnotationComposer,
          $$CachedAddOnsTableCreateCompanionBuilder,
          $$CachedAddOnsTableUpdateCompanionBuilder,
          (
            CachedAddOn,
            BaseReferences<_$CacheDb, $CachedAddOnsTable, CachedAddOn>,
          ),
          CachedAddOn,
          PrefetchHooks Function()
        > {
  $$CachedAddOnsTableTableManager(_$CacheDb db, $CachedAddOnsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedAddOnsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedAddOnsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedAddOnsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> salonId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> pricePaise = const Value.absent(),
                Value<int> extraDurationMinutes = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedAddOnsCompanion(
                id: id,
                salonId: salonId,
                name: name,
                pricePaise: pricePaise,
                extraDurationMinutes: extraDurationMinutes,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String salonId,
                required String name,
                required int pricePaise,
                required int extraDurationMinutes,
                required bool active,
                Value<int> rowid = const Value.absent(),
              }) => CachedAddOnsCompanion.insert(
                id: id,
                salonId: salonId,
                name: name,
                pricePaise: pricePaise,
                extraDurationMinutes: extraDurationMinutes,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedAddOnsTable, CachedAddOn>(table),
                  BaseReferences<_$CacheDb, $CachedAddOnsTable, CachedAddOn>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedAddOnsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDb,
      $CachedAddOnsTable,
      CachedAddOn,
      $$CachedAddOnsTableFilterComposer,
      $$CachedAddOnsTableOrderingComposer,
      $$CachedAddOnsTableAnnotationComposer,
      $$CachedAddOnsTableCreateCompanionBuilder,
      $$CachedAddOnsTableUpdateCompanionBuilder,
      (CachedAddOn, BaseReferences<_$CacheDb, $CachedAddOnsTable, CachedAddOn>),
      CachedAddOn,
      PrefetchHooks Function()
    >;
typedef $$CachedStaffMembersTableCreateCompanionBuilder =
    CachedStaffMembersCompanion Function({
      required String id,
      required String salonId,
      required String name,
      required bool active,
      Value<int> rowid,
    });
typedef $$CachedStaffMembersTableUpdateCompanionBuilder =
    CachedStaffMembersCompanion Function({
      Value<String> id,
      Value<String> salonId,
      Value<String> name,
      Value<bool> active,
      Value<int> rowid,
    });

class $$CachedStaffMembersTableFilterComposer
    extends Composer<_$CacheDb, $CachedStaffMembersTable> {
  $$CachedStaffMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedStaffMembersTableOrderingComposer
    extends Composer<_$CacheDb, $CachedStaffMembersTable> {
  $$CachedStaffMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedStaffMembersTableAnnotationComposer
    extends Composer<_$CacheDb, $CachedStaffMembersTable> {
  $$CachedStaffMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get salonId =>
      $composableBuilder(column: $table.salonId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$CachedStaffMembersTableTableManager
    extends
        RootTableManager<
          _$CacheDb,
          $CachedStaffMembersTable,
          CachedStaff,
          $$CachedStaffMembersTableFilterComposer,
          $$CachedStaffMembersTableOrderingComposer,
          $$CachedStaffMembersTableAnnotationComposer,
          $$CachedStaffMembersTableCreateCompanionBuilder,
          $$CachedStaffMembersTableUpdateCompanionBuilder,
          (
            CachedStaff,
            BaseReferences<_$CacheDb, $CachedStaffMembersTable, CachedStaff>,
          ),
          CachedStaff,
          PrefetchHooks Function()
        > {
  $$CachedStaffMembersTableTableManager(
    _$CacheDb db,
    $CachedStaffMembersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedStaffMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedStaffMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedStaffMembersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> salonId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedStaffMembersCompanion(
                id: id,
                salonId: salonId,
                name: name,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String salonId,
                required String name,
                required bool active,
                Value<int> rowid = const Value.absent(),
              }) => CachedStaffMembersCompanion.insert(
                id: id,
                salonId: salonId,
                name: name,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedStaffMembersTable, CachedStaff>(table),
                  BaseReferences<
                    _$CacheDb,
                    $CachedStaffMembersTable,
                    CachedStaff
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedStaffMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDb,
      $CachedStaffMembersTable,
      CachedStaff,
      $$CachedStaffMembersTableFilterComposer,
      $$CachedStaffMembersTableOrderingComposer,
      $$CachedStaffMembersTableAnnotationComposer,
      $$CachedStaffMembersTableCreateCompanionBuilder,
      $$CachedStaffMembersTableUpdateCompanionBuilder,
      (
        CachedStaff,
        BaseReferences<_$CacheDb, $CachedStaffMembersTable, CachedStaff>,
      ),
      CachedStaff,
      PrefetchHooks Function()
    >;
typedef $$CachedCustomersTableCreateCompanionBuilder =
    CachedCustomersCompanion Function({
      required String id,
      required String salonId,
      Value<String?> name,
      Value<String?> phone,
      Value<DateTime?> lastVisitAt,
      Value<int> balancePaise,
      Value<int> visitCount,
      Value<int> rowid,
    });
typedef $$CachedCustomersTableUpdateCompanionBuilder =
    CachedCustomersCompanion Function({
      Value<String> id,
      Value<String> salonId,
      Value<String?> name,
      Value<String?> phone,
      Value<DateTime?> lastVisitAt,
      Value<int> balancePaise,
      Value<int> visitCount,
      Value<int> rowid,
    });

class $$CachedCustomersTableFilterComposer
    extends Composer<_$CacheDb, $CachedCustomersTable> {
  $$CachedCustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastVisitAt => $composableBuilder(
    column: $table.lastVisitAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get visitCount => $composableBuilder(
    column: $table.visitCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCustomersTableOrderingComposer
    extends Composer<_$CacheDb, $CachedCustomersTable> {
  $$CachedCustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastVisitAt => $composableBuilder(
    column: $table.lastVisitAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get visitCount => $composableBuilder(
    column: $table.visitCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCustomersTableAnnotationComposer
    extends Composer<_$CacheDb, $CachedCustomersTable> {
  $$CachedCustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get salonId =>
      $composableBuilder(column: $table.salonId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<DateTime> get lastVisitAt => $composableBuilder(
    column: $table.lastVisitAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get balancePaise => $composableBuilder(
    column: $table.balancePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get visitCount => $composableBuilder(
    column: $table.visitCount,
    builder: (column) => column,
  );
}

class $$CachedCustomersTableTableManager
    extends
        RootTableManager<
          _$CacheDb,
          $CachedCustomersTable,
          CachedCustomer,
          $$CachedCustomersTableFilterComposer,
          $$CachedCustomersTableOrderingComposer,
          $$CachedCustomersTableAnnotationComposer,
          $$CachedCustomersTableCreateCompanionBuilder,
          $$CachedCustomersTableUpdateCompanionBuilder,
          (
            CachedCustomer,
            BaseReferences<_$CacheDb, $CachedCustomersTable, CachedCustomer>,
          ),
          CachedCustomer,
          PrefetchHooks Function()
        > {
  $$CachedCustomersTableTableManager(_$CacheDb db, $CachedCustomersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedCustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> salonId = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<DateTime?> lastVisitAt = const Value.absent(),
                Value<int> balancePaise = const Value.absent(),
                Value<int> visitCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCustomersCompanion(
                id: id,
                salonId: salonId,
                name: name,
                phone: phone,
                lastVisitAt: lastVisitAt,
                balancePaise: balancePaise,
                visitCount: visitCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String salonId,
                Value<String?> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<DateTime?> lastVisitAt = const Value.absent(),
                Value<int> balancePaise = const Value.absent(),
                Value<int> visitCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCustomersCompanion.insert(
                id: id,
                salonId: salonId,
                name: name,
                phone: phone,
                lastVisitAt: lastVisitAt,
                balancePaise: balancePaise,
                visitCount: visitCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedCustomersTable, CachedCustomer>(table),
                  BaseReferences<
                    _$CacheDb,
                    $CachedCustomersTable,
                    CachedCustomer
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDb,
      $CachedCustomersTable,
      CachedCustomer,
      $$CachedCustomersTableFilterComposer,
      $$CachedCustomersTableOrderingComposer,
      $$CachedCustomersTableAnnotationComposer,
      $$CachedCustomersTableCreateCompanionBuilder,
      $$CachedCustomersTableUpdateCompanionBuilder,
      (
        CachedCustomer,
        BaseReferences<_$CacheDb, $CachedCustomersTable, CachedCustomer>,
      ),
      CachedCustomer,
      PrefetchHooks Function()
    >;
typedef $$CachedVisitsTableCreateCompanionBuilder =
    CachedVisitsCompanion Function({
      required String id,
      required String salonId,
      required String customerId,
      required DateTime completedAt,
      required int finalAmountPaise,
      Value<String> serviceNames,
      Value<int> rowid,
    });
typedef $$CachedVisitsTableUpdateCompanionBuilder =
    CachedVisitsCompanion Function({
      Value<String> id,
      Value<String> salonId,
      Value<String> customerId,
      Value<DateTime> completedAt,
      Value<int> finalAmountPaise,
      Value<String> serviceNames,
      Value<int> rowid,
    });

class $$CachedVisitsTableFilterComposer
    extends Composer<_$CacheDb, $CachedVisitsTable> {
  $$CachedVisitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finalAmountPaise => $composableBuilder(
    column: $table.finalAmountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serviceNames => $composableBuilder(
    column: $table.serviceNames,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedVisitsTableOrderingComposer
    extends Composer<_$CacheDb, $CachedVisitsTable> {
  $$CachedVisitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get salonId => $composableBuilder(
    column: $table.salonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finalAmountPaise => $composableBuilder(
    column: $table.finalAmountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serviceNames => $composableBuilder(
    column: $table.serviceNames,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedVisitsTableAnnotationComposer
    extends Composer<_$CacheDb, $CachedVisitsTable> {
  $$CachedVisitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get salonId =>
      $composableBuilder(column: $table.salonId, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get finalAmountPaise => $composableBuilder(
    column: $table.finalAmountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serviceNames => $composableBuilder(
    column: $table.serviceNames,
    builder: (column) => column,
  );
}

class $$CachedVisitsTableTableManager
    extends
        RootTableManager<
          _$CacheDb,
          $CachedVisitsTable,
          CachedVisit,
          $$CachedVisitsTableFilterComposer,
          $$CachedVisitsTableOrderingComposer,
          $$CachedVisitsTableAnnotationComposer,
          $$CachedVisitsTableCreateCompanionBuilder,
          $$CachedVisitsTableUpdateCompanionBuilder,
          (
            CachedVisit,
            BaseReferences<_$CacheDb, $CachedVisitsTable, CachedVisit>,
          ),
          CachedVisit,
          PrefetchHooks Function()
        > {
  $$CachedVisitsTableTableManager(_$CacheDb db, $CachedVisitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedVisitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedVisitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedVisitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> salonId = const Value.absent(),
                Value<String> customerId = const Value.absent(),
                Value<DateTime> completedAt = const Value.absent(),
                Value<int> finalAmountPaise = const Value.absent(),
                Value<String> serviceNames = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedVisitsCompanion(
                id: id,
                salonId: salonId,
                customerId: customerId,
                completedAt: completedAt,
                finalAmountPaise: finalAmountPaise,
                serviceNames: serviceNames,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String salonId,
                required String customerId,
                required DateTime completedAt,
                required int finalAmountPaise,
                Value<String> serviceNames = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedVisitsCompanion.insert(
                id: id,
                salonId: salonId,
                customerId: customerId,
                completedAt: completedAt,
                finalAmountPaise: finalAmountPaise,
                serviceNames: serviceNames,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedVisitsTable, CachedVisit>(table),
                  BaseReferences<_$CacheDb, $CachedVisitsTable, CachedVisit>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedVisitsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDb,
      $CachedVisitsTable,
      CachedVisit,
      $$CachedVisitsTableFilterComposer,
      $$CachedVisitsTableOrderingComposer,
      $$CachedVisitsTableAnnotationComposer,
      $$CachedVisitsTableCreateCompanionBuilder,
      $$CachedVisitsTableUpdateCompanionBuilder,
      (CachedVisit, BaseReferences<_$CacheDb, $CachedVisitsTable, CachedVisit>),
      CachedVisit,
      PrefetchHooks Function()
    >;
typedef $$CacheStampsTableCreateCompanionBuilder =
    CacheStampsCompanion Function({
      required String key,
      required DateTime refreshedAt,
      Value<int> rowid,
    });
typedef $$CacheStampsTableUpdateCompanionBuilder =
    CacheStampsCompanion Function({
      Value<String> key,
      Value<DateTime> refreshedAt,
      Value<int> rowid,
    });

class $$CacheStampsTableFilterComposer
    extends Composer<_$CacheDb, $CacheStampsTable> {
  $$CacheStampsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheStampsTableOrderingComposer
    extends Composer<_$CacheDb, $CacheStampsTable> {
  $$CacheStampsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheStampsTableAnnotationComposer
    extends Composer<_$CacheDb, $CacheStampsTable> {
  $$CacheStampsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );
}

class $$CacheStampsTableTableManager
    extends
        RootTableManager<
          _$CacheDb,
          $CacheStampsTable,
          CacheStamp,
          $$CacheStampsTableFilterComposer,
          $$CacheStampsTableOrderingComposer,
          $$CacheStampsTableAnnotationComposer,
          $$CacheStampsTableCreateCompanionBuilder,
          $$CacheStampsTableUpdateCompanionBuilder,
          (
            CacheStamp,
            BaseReferences<_$CacheDb, $CacheStampsTable, CacheStamp>,
          ),
          CacheStamp,
          PrefetchHooks Function()
        > {
  $$CacheStampsTableTableManager(_$CacheDb db, $CacheStampsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheStampsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheStampsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheStampsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<DateTime> refreshedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheStampsCompanion(
                key: key,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required DateTime refreshedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheStampsCompanion.insert(
                key: key,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheStampsTable, CacheStamp>(table),
                  BaseReferences<_$CacheDb, $CacheStampsTable, CacheStamp>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheStampsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDb,
      $CacheStampsTable,
      CacheStamp,
      $$CacheStampsTableFilterComposer,
      $$CacheStampsTableOrderingComposer,
      $$CacheStampsTableAnnotationComposer,
      $$CacheStampsTableCreateCompanionBuilder,
      $$CacheStampsTableUpdateCompanionBuilder,
      (CacheStamp, BaseReferences<_$CacheDb, $CacheStampsTable, CacheStamp>),
      CacheStamp,
      PrefetchHooks Function()
    >;

class $CacheDbManager {
  final _$CacheDb _db;
  $CacheDbManager(this._db);
  $$CachedServicesTableTableManager get cachedServices =>
      $$CachedServicesTableTableManager(_db, _db.cachedServices);
  $$CachedAddOnsTableTableManager get cachedAddOns =>
      $$CachedAddOnsTableTableManager(_db, _db.cachedAddOns);
  $$CachedStaffMembersTableTableManager get cachedStaffMembers =>
      $$CachedStaffMembersTableTableManager(_db, _db.cachedStaffMembers);
  $$CachedCustomersTableTableManager get cachedCustomers =>
      $$CachedCustomersTableTableManager(_db, _db.cachedCustomers);
  $$CachedVisitsTableTableManager get cachedVisits =>
      $$CachedVisitsTableTableManager(_db, _db.cachedVisits);
  $$CacheStampsTableTableManager get cacheStamps =>
      $$CacheStampsTableTableManager(_db, _db.cacheStamps);
}
