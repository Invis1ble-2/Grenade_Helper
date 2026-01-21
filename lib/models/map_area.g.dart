// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_area.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetMapAreaCollection on Isar {
  IsarCollection<MapArea> get mapAreas => this.collection();
}

const MapAreaSchema = CollectionSchema(
  name: r'MapArea',
  id: 4024579562014672876,
  properties: {
    r'colorValue': PropertySchema(
      id: 0,
      name: r'colorValue',
      type: IsarType.long,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'layerId': PropertySchema(
      id: 2,
      name: r'layerId',
      type: IsarType.long,
    ),
    r'mapId': PropertySchema(
      id: 3,
      name: r'mapId',
      type: IsarType.long,
    ),
    r'name': PropertySchema(
      id: 4,
      name: r'name',
      type: IsarType.string,
    ),
    r'strokes': PropertySchema(
      id: 5,
      name: r'strokes',
      type: IsarType.string,
    ),
    r'tagId': PropertySchema(
      id: 6,
      name: r'tagId',
      type: IsarType.long,
    )
  },
  estimateSize: _mapAreaEstimateSize,
  serialize: _mapAreaSerialize,
  deserialize: _mapAreaDeserialize,
  deserializeProp: _mapAreaDeserializeProp,
  idName: r'id',
  indexes: {
    r'name': IndexSchema(
      id: 879695947855722453,
      name: r'name',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'name',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'mapId': IndexSchema(
      id: -6043270103971104264,
      name: r'mapId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'mapId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _mapAreaGetId,
  getLinks: _mapAreaGetLinks,
  attach: _mapAreaAttach,
  version: '3.3.0',
);

int _mapAreaEstimateSize(
  MapArea object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.strokes.length * 3;
  return bytesCount;
}

void _mapAreaSerialize(
  MapArea object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.colorValue);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeLong(offsets[2], object.layerId);
  writer.writeLong(offsets[3], object.mapId);
  writer.writeString(offsets[4], object.name);
  writer.writeString(offsets[5], object.strokes);
  writer.writeLong(offsets[6], object.tagId);
}

MapArea _mapAreaDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = MapArea(
    colorValue: reader.readLong(offsets[0]),
    createdAt: reader.readDateTime(offsets[1]),
    layerId: reader.readLongOrNull(offsets[2]),
    mapId: reader.readLong(offsets[3]),
    name: reader.readString(offsets[4]),
    strokes: reader.readString(offsets[5]),
    tagId: reader.readLong(offsets[6]),
  );
  object.id = id;
  return object;
}

P _mapAreaDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readLongOrNull(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _mapAreaGetId(MapArea object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _mapAreaGetLinks(MapArea object) {
  return [];
}

void _mapAreaAttach(IsarCollection<dynamic> col, Id id, MapArea object) {
  object.id = id;
}

extension MapAreaQueryWhereSort on QueryBuilder<MapArea, MapArea, QWhere> {
  QueryBuilder<MapArea, MapArea, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhere> anyMapId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'mapId'),
      );
    });
  }
}

extension MapAreaQueryWhere on QueryBuilder<MapArea, MapArea, QWhereClause> {
  QueryBuilder<MapArea, MapArea, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> nameEqualTo(String name) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'name',
        value: [name],
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> nameNotEqualTo(
      String name) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [],
              upper: [name],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [name],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [name],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [],
              upper: [name],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> mapIdEqualTo(int mapId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'mapId',
        value: [mapId],
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> mapIdNotEqualTo(int mapId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'mapId',
              lower: [],
              upper: [mapId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'mapId',
              lower: [mapId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'mapId',
              lower: [mapId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'mapId',
              lower: [],
              upper: [mapId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> mapIdGreaterThan(
    int mapId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'mapId',
        lower: [mapId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> mapIdLessThan(
    int mapId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'mapId',
        lower: [],
        upper: [mapId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterWhereClause> mapIdBetween(
    int lowerMapId,
    int upperMapId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'mapId',
        lower: [lowerMapId],
        includeLower: includeLower,
        upper: [upperMapId],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension MapAreaQueryFilter
    on QueryBuilder<MapArea, MapArea, QFilterCondition> {
  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> colorValueEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'colorValue',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> colorValueGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'colorValue',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> colorValueLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'colorValue',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> colorValueBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'colorValue',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> createdAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> layerIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'layerId',
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> layerIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'layerId',
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> layerIdEqualTo(
      int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'layerId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> layerIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'layerId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> layerIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'layerId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> layerIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'layerId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> mapIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mapId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> mapIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mapId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> mapIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mapId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> mapIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mapId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'strokes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'strokes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'strokes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'strokes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'strokes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'strokes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'strokes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'strokes',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'strokes',
        value: '',
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> strokesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'strokes',
        value: '',
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> tagIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tagId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> tagIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tagId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> tagIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tagId',
        value: value,
      ));
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterFilterCondition> tagIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tagId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension MapAreaQueryObject
    on QueryBuilder<MapArea, MapArea, QFilterCondition> {}

extension MapAreaQueryLinks
    on QueryBuilder<MapArea, MapArea, QFilterCondition> {}

extension MapAreaQuerySortBy on QueryBuilder<MapArea, MapArea, QSortBy> {
  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByColorValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByColorValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByLayerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layerId', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByLayerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layerId', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByMapId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mapId', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByMapIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mapId', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByStrokes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'strokes', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByStrokesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'strokes', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByTagId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> sortByTagIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.desc);
    });
  }
}

extension MapAreaQuerySortThenBy
    on QueryBuilder<MapArea, MapArea, QSortThenBy> {
  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByColorValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByColorValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByLayerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layerId', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByLayerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layerId', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByMapId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mapId', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByMapIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mapId', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByStrokes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'strokes', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByStrokesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'strokes', Sort.desc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByTagId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.asc);
    });
  }

  QueryBuilder<MapArea, MapArea, QAfterSortBy> thenByTagIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.desc);
    });
  }
}

extension MapAreaQueryWhereDistinct
    on QueryBuilder<MapArea, MapArea, QDistinct> {
  QueryBuilder<MapArea, MapArea, QDistinct> distinctByColorValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'colorValue');
    });
  }

  QueryBuilder<MapArea, MapArea, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<MapArea, MapArea, QDistinct> distinctByLayerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'layerId');
    });
  }

  QueryBuilder<MapArea, MapArea, QDistinct> distinctByMapId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mapId');
    });
  }

  QueryBuilder<MapArea, MapArea, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MapArea, MapArea, QDistinct> distinctByStrokes(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'strokes', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MapArea, MapArea, QDistinct> distinctByTagId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tagId');
    });
  }
}

extension MapAreaQueryProperty
    on QueryBuilder<MapArea, MapArea, QQueryProperty> {
  QueryBuilder<MapArea, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<MapArea, int, QQueryOperations> colorValueProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'colorValue');
    });
  }

  QueryBuilder<MapArea, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<MapArea, int?, QQueryOperations> layerIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'layerId');
    });
  }

  QueryBuilder<MapArea, int, QQueryOperations> mapIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mapId');
    });
  }

  QueryBuilder<MapArea, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<MapArea, String, QQueryOperations> strokesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'strokes');
    });
  }

  QueryBuilder<MapArea, int, QQueryOperations> tagIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tagId');
    });
  }
}
