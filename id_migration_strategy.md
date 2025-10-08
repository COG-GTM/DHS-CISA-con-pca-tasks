# ObjectID to UUID Migration Strategy

**Ticket:** MBA-322 - Phase 1 Database Schema Design for PostgreSQL Migration  
**Repository:** COG-GTM/DHS-CISA-con-pca-tasks  
**Analysis Date:** October 8, 2025  
**Analyst:** Devin AI

---

## Executive Summary

This document analyzes the current MongoDB ObjectID usage and provides a comprehensive strategy for migrating to PostgreSQL UUIDs while maintaining backward compatibility with existing HTTP endpoints and data references.

---

## Current ObjectID Implementation

### MongoDB ObjectID Structure

MongoDB ObjectIDs are 12-byte identifiers typically represented as 24-character hexadecimal strings:

```
Format: 4-byte timestamp | 5-byte random | 3-byte counter
Example: 507f1f77bcf86cd799439011
Length: 24 hex characters = 12 bytes
```

### ObjectID Usage in con-pca-tasks

#### 1. Conversion Pattern

**Location:** `database/collections/cycles.go:26` and `subscriptions.go:70`

```go
func GetCycle(id string) (Cycle, error) {
    var c Cycle
    // Convert the string id to an ObjectID
    objectId, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        return c, err
    }
    err = db.CyclesCollection.
        FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).
        Decode(&c)
    return c, nil
}
```

**Pattern:**
1. HTTP endpoint receives string ID (24-char hex)
2. Convert string to ObjectID: `primitive.ObjectIDFromHex(id)`
3. Query MongoDB with ObjectID
4. No ObjectID generation in con-pca-tasks (read-only)

#### 2. HTTP Endpoint Usage

**Location:** `controllers/controllers.go:21-22`

```go
func emailReportHandler(w http.ResponseWriter, r *http.Request) {
    cycleId := chi.URLParam(r, "cycle_id")  // String from URL path
    reportType := chi.URLParam(r, "report_type")
    notifications.Manager(cycleId, reportType)  // Pass string directly
}
```

**Endpoint Format:**
```
GET /tasks/{cycle_id}/reports/{report_type}/email
Example: GET /tasks/507f1f77bcf86cd799439011/reports/cycle/email
```

**Critical Observation:** 
- IDs are passed as strings through HTTP
- No validation of format at endpoint level
- Application expects 24-character hex strings

#### 3. Foreign Key References

**Location:** `database/collections/cycles.go:12`

```go
type Cycle struct {
    SubscriptionId string `bson:"subscription_id"`  // Stored as string, not ObjectID!
    ...
}
```

**Key Finding:** Foreign key references are stored as **strings** in the Go structs, not as ObjectID types.

---

## PostgreSQL UUID Strategy

### UUID Format and Generation

PostgreSQL UUIDs are 128-bit (16-byte) identifiers:

```
Format: 8-4-4-4-12 hex characters with hyphens
Example: 550e8400-e29b-41d4-a716-446655440000
Length: 36 characters (32 hex + 4 hyphens) = 16 bytes
```

### Proposed Schema (from MBA-322)

```sql
CREATE TABLE cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    ...
);

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ...
);
```

---

## Migration Challenges

### Challenge 1: Format Incompatibility

**Problem:**
- MongoDB ObjectID: 24 hex chars (e.g., `507f1f77bcf86cd799439011`)
- PostgreSQL UUID: 36 chars with hyphens (e.g., `550e8400-e29b-41d4-a716-446655440000`)

**Impact:**
- ❌ Cannot directly convert ObjectID hex string to UUID
- ❌ HTTP endpoints expect 24-character IDs
- ❌ Existing API clients send ObjectID format
- ❌ Stored references in other systems may use ObjectID format

### Challenge 2: Backward Compatibility

**Problem:**
- Existing cycles, subscriptions already have MongoDB ObjectIDs
- External systems may reference these IDs
- HTTP endpoints cannot change format without breaking clients

### Challenge 3: Foreign Key Migration

**Problem:**
- `subscription_id` fields currently store ObjectID strings
- Must maintain referential integrity during migration
- All references must convert consistently

---

## Migration Solutions

### Solution 1: Direct UUID Migration (Breaking Change)

**Approach:** Generate new UUIDs for all records, abandon old ObjectIDs

**Process:**
1. Export data from MongoDB
2. Generate new UUID for each record
3. Update all foreign key references to new UUIDs
4. Import to PostgreSQL
5. Update HTTP endpoints to accept UUID format

**Pros:**
- ✅ Clean PostgreSQL implementation
- ✅ Native UUID handling
- ✅ Standard approach

**Cons:**
- ❌ **Breaking change** for API clients
- ❌ External references become invalid
- ❌ Cannot maintain URLs/bookmarks
- ❌ Requires coordinated deployment

**Verdict:** ❌ **Not Recommended** - Too disruptive for production system

---

### Solution 2: ObjectID-to-UUID Conversion (Hybrid Approach)

**Approach:** Convert 12-byte ObjectID to UUID v4 format

**Conversion Formula:**
```
ObjectID: 507f1f77bcf86cd799439011 (24 hex chars = 12 bytes)
Pad to 16 bytes: 507f1f77bcf86cd799439011 + 00000000 (8 zero bytes)
Format as UUID: 507f1f77-bcf8-6cd7-9943-901100000000
```

**Implementation:**
```python
# Python conversion example
def objectid_to_uuid(objectid_hex):
    # Pad 12-byte ObjectID to 16 bytes
    padded = objectid_hex + '0' * 8
    # Insert UUID hyphens
    return f"{padded[0:8]}-{padded[8:12]}-{padded[12:16]}-{padded[16:20]}-{padded[20:32]}"

# Example
objectid = "507f1f77bcf86cd799439011"
uuid_str = objectid_to_uuid(objectid)
# Result: "507f1f77-bcf8-6cd7-9943-901100000000"
```

**Pros:**
- ✅ Deterministic conversion
- ✅ Can convert back if needed
- ✅ Existing ObjectIDs map to valid UUIDs

**Cons:**
- ❌ HTTP endpoints still need to accept 24-char format
- ❌ Clients must convert before API call
- ❌ Not standard UUID generation pattern
- ❌ Padding with zeros reveals it's not a true UUID

**Verdict:** ⚠️ **Possible but Complex** - Requires client-side changes

---

### Solution 3: Dual-ID Strategy with ObjectID Compatibility (Recommended)

**Approach:** Store UUIDs as primary keys, maintain ObjectID mapping for compatibility

**Schema Design:**
```sql
CREATE TABLE cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_objectid VARCHAR(24) UNIQUE,  -- Original MongoDB ObjectID
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    ...
);

CREATE INDEX idx_cycles_legacy_objectid ON cycles(legacy_objectid);

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_objectid VARCHAR(24) UNIQUE,
    ...
);

CREATE INDEX idx_subscriptions_legacy_objectid ON subscriptions(legacy_objectid);
```

**HTTP Endpoint Compatibility Layer:**
```go
// Updated GetCycle function
func GetCycle(id string) (Cycle, error) {
    var c Cycle
    
    // Try to parse as UUID first (new format)
    uuid, err := uuid.Parse(id)
    if err == nil {
        // Query by UUID
        err = db.CyclesCollection.
            FindOne(db.Ctx, bson.D{{Key: "id", Value: uuid}}).
            Decode(&c)
        return c, err
    }
    
    // Fallback: treat as legacy ObjectID (24-char hex)
    if len(id) == 24 {
        err = db.CyclesCollection.
            FindOne(db.Ctx, bson.D{{Key: "legacy_objectid", Value: id}}).
            Decode(&c)
        return c, err
    }
    
    return c, errors.New("invalid id format")
}
```

**Pros:**
- ✅ **Backward compatible** - existing ObjectID URLs still work
- ✅ New records use proper UUIDs
- ✅ No breaking changes for API clients
- ✅ Gradual migration possible
- ✅ Can deprecate ObjectID support later

**Cons:**
- ❌ Additional storage for legacy_objectid column
- ❌ Dual query paths add complexity
- ❌ Slightly slower lookups via legacy ID (indexed but not PK)

**Verdict:** ✅ **RECOMMENDED** - Best balance of compatibility and PostgreSQL best practices

---

### Solution 4: Keep ObjectID Format (String Primary Keys)

**Approach:** Store ObjectIDs as strings in PostgreSQL, skip UUID entirely

**Schema:**
```sql
CREATE TABLE cycles (
    id VARCHAR(24) PRIMARY KEY,  -- Store ObjectID as string
    subscription_id VARCHAR(24) NOT NULL REFERENCES subscriptions(id),
    ...
);
```

**Pros:**
- ✅ Zero breaking changes
- ✅ Simple migration
- ✅ No compatibility layer needed

**Cons:**
- ❌ Not PostgreSQL best practice
- ❌ Miss UUID benefits (uniqueness guarantees, native support)
- ❌ 24-char strings less efficient than 16-byte UUIDs
- ❌ Cannot use `gen_random_uuid()` for new records
- ❌ Technical debt remains

**Verdict:** ❌ **Not Recommended** - Defeats purpose of PostgreSQL migration

---

## Recommended Migration Strategy: Dual-ID Approach

### Phase 1: Schema Creation

```sql
-- Migrations with dual ID support
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_objectid VARCHAR(24) UNIQUE,
    -- ... other fields
);

CREATE TABLE cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_objectid VARCHAR(24) UNIQUE,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    -- ... other fields
);

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_objectid VARCHAR(24) UNIQUE,
    -- ... other fields
);

CREATE TABLE templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_objectid VARCHAR(24) UNIQUE,
    -- ... other fields
);

-- Indexes for legacy lookups
CREATE INDEX idx_cycles_legacy_objectid ON cycles(legacy_objectid);
CREATE INDEX idx_subscriptions_legacy_objectid ON subscriptions(legacy_objectid);
CREATE INDEX idx_notifications_legacy_objectid ON notifications(legacy_objectid);
CREATE INDEX idx_templates_legacy_objectid ON templates(legacy_objectid);
```

### Phase 2: Data Migration

```python
# Pseudo-code for data migration
for record in mongodb_collection.find():
    new_record = {
        'id': uuid.uuid4(),  # Generate new UUID
        'legacy_objectid': str(record['_id']),  # Preserve ObjectID
        # ... other fields
    }
    postgresql_insert(new_record)
```

**Foreign Key Migration:**
```python
# Convert foreign key references
for cycle in mongodb_cycles.find():
    subscription_objectid = cycle['subscription_id']
    # Lookup new UUID by legacy ObjectID
    new_subscription_id = postgres.query(
        "SELECT id FROM subscriptions WHERE legacy_objectid = %s",
        [subscription_objectid]
    )
    cycle['subscription_id'] = new_subscription_id
```

### Phase 3: Application Code Updates

**Updated Database Access Layer:**

```go
// database/postgres.go (new file)
package database

import (
    "github.com/google/uuid"
    "github.com/lib/pq"
)

// GetCycleByID supports both UUID and legacy ObjectID
func GetCycleByID(id string) (Cycle, error) {
    var c Cycle
    
    // Try UUID first (36-char with hyphens)
    parsedUUID, err := uuid.Parse(id)
    if err == nil {
        query := "SELECT * FROM cycles WHERE id = $1"
        err = db.Get(&c, query, parsedUUID)
        if err == nil {
            return c, nil
        }
    }
    
    // Fallback to legacy ObjectID (24-char hex)
    if len(id) == 24 && isHex(id) {
        query := "SELECT * FROM cycles WHERE legacy_objectid = $1"
        err = db.Get(&c, query, id)
        return c, err
    }
    
    return c, errors.New("invalid ID format")
}

func isHex(s string) bool {
    for _, c := range s {
        if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
            return false
        }
    }
    return true
}
```

**HTTP Endpoint Updates:**
```go
// No changes needed - accepts string IDs as before
func emailReportHandler(w http.ResponseWriter, r *http.Request) {
    cycleId := chi.URLParam(r, "cycle_id")  // Still accepts strings
    // GetCycleByID handles both formats internally
    notifications.Manager(cycleId, reportType)
}
```

### Phase 4: API Response Format

**Support both ID formats in responses:**

```go
type CycleResponse struct {
    ID             uuid.UUID `json:"id"`               // New UUID (primary)
    LegacyObjectID string    `json:"legacy_id,omitempty"` // Optional legacy ID
    // ... other fields
}
```

**Example Response:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "legacy_id": "507f1f77bcf86cd799439011",
    "subscription_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "start_date": "2025-10-08T10:00:00Z"
}
```

### Phase 5: Gradual Deprecation

**Timeline:**
1. **Months 1-3:** Both formats work, document UUID as preferred
2. **Months 4-6:** Encourage client migration to UUID
3. **Months 7-9:** Deprecation warnings for ObjectID usage
4. **Month 10+:** Remove legacy_objectid support

**Deprecation Strategy:**
```go
func GetCycleByID(id string) (Cycle, error) {
    if len(id) == 24 && isHex(id) {
        // Log deprecation warning
        log.Warn("Legacy ObjectID used, please migrate to UUID format")
        // Increment deprecation metric for monitoring
        metrics.IncrementDeprecatedIDUsage()
    }
    // ... rest of function
}
```

---

## Testing Strategy

### Unit Tests

```go
func TestGetCycleWithUUID(t *testing.T) {
    // Test new UUID format
    uuid := "550e8400-e29b-41d4-a716-446655440000"
    cycle, err := GetCycleByID(uuid)
    assert.NoError(t, err)
    assert.Equal(t, uuid, cycle.ID.String())
}

func TestGetCycleWithLegacyObjectID(t *testing.T) {
    // Test backward compatibility
    objectID := "507f1f77bcf86cd799439011"
    cycle, err := GetCycleByID(objectID)
    assert.NoError(t, err)
    assert.Equal(t, objectID, cycle.LegacyObjectID)
}

func TestGetCycleWithInvalidID(t *testing.T) {
    // Test invalid format
    _, err := GetCycleByID("invalid-id")
    assert.Error(t, err)
}
```

### Integration Tests

```bash
# Test HTTP endpoints with both formats
curl http://localhost:8080/tasks/550e8400-e29b-41d4-a716-446655440000/reports/cycle/email
curl http://localhost:8080/tasks/507f1f77bcf86cd799439011/reports/cycle/email
```

### Migration Test

```sql
-- Verify all foreign keys resolved correctly
SELECT COUNT(*) 
FROM cycles c
LEFT JOIN subscriptions s ON c.subscription_id = s.id
WHERE s.id IS NULL;
-- Should return 0

-- Verify legacy IDs unique and not null for migrated records
SELECT COUNT(*) 
FROM cycles 
WHERE legacy_objectid IS NULL OR legacy_objectid = '';
-- Should return 0 for migrated data

-- Verify UUID uniqueness
SELECT COUNT(DISTINCT id) = COUNT(*) 
FROM cycles;
-- Should return true
```

---

## Performance Considerations

### Storage Comparison

| Format | Storage Size | Index Size | Performance |
|--------|--------------|------------|-------------|
| UUID (16 bytes) | 16 bytes | Efficient | Fast |
| ObjectID String (24 chars) | 24 bytes | Larger | Slower |
| Legacy column overhead | +24 bytes | +index | Lookup penalty |

**Impact:** ~50% storage increase during transition (dual IDs), but UUID primary key lookups remain fast.

### Query Performance

```sql
-- Primary key lookup (UUID) - fastest
SELECT * FROM cycles WHERE id = '550e8400-e29b-41d4-a716-446655440000';

-- Secondary index lookup (legacy) - slightly slower
SELECT * FROM cycles WHERE legacy_objectid = '507f1f77bcf86cd799439011';
```

**Estimated Impact:** Legacy ID lookups add ~5-10% overhead compared to primary key, but still fast with index.

---

## Risks and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Foreign key mismatch during migration | Medium | High | Comprehensive validation queries |
| Legacy ID collisions | Low | High | Unique constraint enforces safety |
| Client breakage from UUID format | Low | Medium | Backward compatibility layer |
| Performance degradation | Low | Low | Indexed legacy_objectid |
| Incomplete client migration | Medium | Low | Extended deprecation timeline |

---

## Rollback Strategy

If issues arise:

1. **Keep MongoDB running** during initial PostgreSQL deployment
2. **Maintain dual writes** to both databases temporarily
3. **Switch back to MongoDB** if critical issues found
4. **Legacy ObjectID** ensures MongoDB queries work unchanged

---

## Recommendations Summary

### Primary Recommendation: ✅ Dual-ID Strategy

1. **Implement Solution 3** (Dual-ID with legacy ObjectID support)
2. **Add legacy_objectid column** to all tables with UNIQUE constraint
3. **Update query functions** to accept both UUID and ObjectID formats
4. **Maintain backward compatibility** for existing API clients
5. **Plan gradual deprecation** over 6-12 months

### Implementation Priority

1. **High Priority:** Implement dual-ID schema and query layer
2. **Medium Priority:** Add monitoring for legacy ID usage
3. **Low Priority:** Client migration documentation and tools

### Success Criteria

- ✅ All existing ObjectID-based URLs continue to work
- ✅ New records use UUID primary keys
- ✅ No breaking changes for API clients
- ✅ Foreign key relationships maintained correctly
- ✅ Performance remains acceptable (<10% degradation for legacy lookups)

---

**Document Version:** 1.0  
**Status:** RECOMMENDED APPROACH DEFINED  
**Next Steps:** Implement dual-ID schema and test with sample data
