# ObjectID to UUID Migration Strategy

**Ticket:** MBA-322 - Phase 1 Database Schema Design  
**Analysis Date:** October 8, 2025  
**Related Documents:** write_operations_analysis.md, nested_document_strategy.md

## Executive Summary

This document analyzes the current MongoDB ObjectID system and provides a comprehensive strategy for migrating to PostgreSQL UUIDs. The analysis covers ID format compatibility, HTTP endpoint implications, and a detailed migration plan.

### Key Findings

1. ✅ **Direct Conversion Impossible:** MongoDB ObjectIDs (24-char hex) cannot be directly converted to standard UUIDs
2. ✅ **HTTP Compatibility:** All HTTP endpoints use string IDs, so format is transparent to API clients
3. ⚠️ **Mapping Required:** Need ID mapping table during migration to maintain references
4. ✅ **UUID v4 Recommended:** Use `gen_random_uuid()` for new records in PostgreSQL
5. ⚠️ **Foreign Key Challenge:** Must preserve all references during migration

## 1. Current ObjectID System Analysis

### 1.1 MongoDB ObjectID Format

**Structure:** 24-character hexadecimal string
```
507f1f77bcf86cd799439011
│       │       │       │
timestamp counter  random
```

**Components:**
- 4 bytes: Timestamp (seconds since Unix epoch)
- 5 bytes: Random value
- 3 bytes: Incrementing counter

**Example from codebase:**
```go
// database/collections/cycles.go:26
objectId, err := primitive.ObjectIDFromHex(id)
```

### 1.2 Current Usage Patterns

#### In con-pca-tasks (Go)

```go
// Read operations - convert string to ObjectID
func GetCycle(id string) (Cycle, error) {
    objectId, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        return Cycle{}, err
    }
    var c Cycle
    err = db.CycleCollection.FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).Decode(&c)
    return c, err
}

// Similar pattern in:
// - GetSubscription (subscriptions.go:51)
// - GetNotification (notifications.go:28)
// - GetPhish (phishes.go:17) - Uses name instead of ID
```

#### In con-pca-api (Python)

```python
# manager.py:53-58
def document_query(self, document_id):
    """Get query for a document by id."""
    if type(document_id) is str:
        return {"_id": ObjectId(document_id)}
    elif type(document_id) is ObjectId:
        return {"_id": document_id}

# Insert returns string ID
# manager.py:243-249
def save(self, data):
    result = self.db.insert_one(self.load_data(data))
    return {"_id": str(result.inserted_id)}  # Returns hex string
```

### 1.3 HTTP Endpoint Analysis

All HTTP endpoints accept and return string IDs:

```python
# From con-pca-api routing
/api/v1/subscriptions/<subscription_id>
/api/v1/cycles/<cycle_id>
/api/v1/templates/<template_id>
/api/v1/notifications/<notification_id>

# From con-pca-tasks routing (controller/controllers.go)
/tasks/{cycle_id}/reports/{report_type}/email
```

**Critical Finding:** Endpoints use string parameters, making the internal format transparent to API clients.

## 2. UUID Format Analysis

### 2.1 PostgreSQL UUID Format

**Structure:** 36-character string with hyphens (32 hex digits + 4 hyphens)
```
550e8400-e29b-41d4-a716-446655440000
│       │   │   │   │   │
time_low│   │   │   │   │
    time_mid   │   │   │
        version│   │   │
            variant    │
                    node
```

**UUID v4 (Random):** Recommended for new records
- 122 random bits
- Generated with `gen_random_uuid()` in PostgreSQL
- Globally unique without coordination

### 2.2 Format Comparison

| Aspect | MongoDB ObjectID | PostgreSQL UUID |
|--------|------------------|-----------------|
| **String Length** | 24 characters | 36 characters (with hyphens) |
| **Format** | Hex only | Hex with hyphens |
| **Example** | `507f1f77bcf86cd799439011` | `550e8400-e29b-41d4-a716-446655440000` |
| **Binary Size** | 12 bytes | 16 bytes |
| **Can Convert?** | ❌ No | ❌ No |
| **Generation** | MongoDB driver | PostgreSQL `gen_random_uuid()` |
| **Timestamp** | ✅ Embedded | ❌ Not in UUID v4 |

### 2.3 Conversion Possibilities Explored

#### Option 1: Pad ObjectID to UUID Format
```
ObjectID: 507f1f77bcf86cd799439011 (24 chars)
Padded:   507f1f77-bcf8-6cd7-9943-901100000000 (36 chars)
```
❌ **Problem:** Not a valid UUID - fails UUID validation, wrong format

#### Option 2: Hash ObjectID to UUID
```python
import hashlib
import uuid

def objectid_to_uuid(objectid_str):
    # Generate deterministic UUID from ObjectID
    hash_bytes = hashlib.md5(objectid_str.encode()).digest()
    return str(uuid.UUID(bytes=hash_bytes))
```
⚠️ **Problem:** One-way conversion - can't reverse; still creates new ID

#### Option 3: Keep as String
```sql
CREATE TABLE cycles (
    id VARCHAR(24) PRIMARY KEY,  -- Store ObjectID as-is
    ...
);
```
❌ **Problem:** Loses PostgreSQL UUID benefits (validation, storage efficiency, indexing)

**Conclusion:** Direct conversion is not feasible. Must generate new UUIDs and maintain mapping.

## 3. Migration Strategy

### 3.1 Recommended Approach: ID Mapping Table

Create a temporary mapping table during migration to preserve references:

```sql
CREATE TABLE id_migration_mapping (
    collection_name VARCHAR(50) NOT NULL,
    mongodb_id VARCHAR(24) NOT NULL,
    postgres_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (collection_name, mongodb_id)
);

CREATE INDEX idx_id_migration_postgres ON id_migration_mapping(collection_name, postgres_id);
```

### 3.2 Migration Process

#### Phase 1: Create Mapping (During Data Migration)

```python
def migrate_collection(collection_name, mongo_collection, pg_cursor):
    """
    Migrate a collection from MongoDB to PostgreSQL
    """
    mapping = {}
    
    for mongo_doc in mongo_collection.find():
        # Generate new UUID for PostgreSQL
        pg_id = uuid.uuid4()
        
        # Store mapping
        mapping[str(mongo_doc['_id'])] = str(pg_id)
        
        # Insert mapping record
        pg_cursor.execute("""
            INSERT INTO id_migration_mapping (collection_name, mongodb_id, postgres_id)
            VALUES (%s, %s, %s)
        """, (collection_name, str(mongo_doc['_id']), str(pg_id)))
        
        # Insert document with new UUID
        # ... (convert document and insert)
    
    return mapping
```

#### Phase 2: Migrate Collections with Dependencies

**Order of Migration** (respecting foreign keys):

1. **Independent collections** (no FKs):
   - templates
   - notifications

2. **Customer-dependent** (if migrating customers):
   - customers (if in scope)

3. **Subscription-dependent**:
   - subscriptions (FK: customer_id - keep as string if not migrating customers)
   - primary_contacts (FK: subscription_id)

4. **Cycle-dependent**:
   - cycles (FK: subscription_id)
   - subscription_tasks (FK: subscription_id)

5. **Target-dependent**:
   - targets (FK: cycle_id, subscription_id, template_id)
   - target_timeline_events (FK: target_id)

6. **Test-dependent**:
   - subscription_test_results (FK: subscription_id, template_id)
   - test_timeline_events (FK: test_result_id)

7. **Notification/Task history**:
   - subscription_notification_history (FK: subscription_id)

#### Phase 3: Resolve Foreign Key References

```python
def resolve_foreign_keys(collection_name, mongo_doc, mapping_tables):
    """
    Convert MongoDB ObjectID references to PostgreSQL UUIDs
    """
    # Example: Convert subscription_id in cycle
    if collection_name == 'cycle':
        if 'subscription_id' in mongo_doc:
            old_id = str(mongo_doc['subscription_id'])
            mongo_doc['subscription_id'] = mapping_tables['subscription'].get(old_id)
    
    # Example: Convert array of template IDs
    if 'template_ids' in mongo_doc:
        mongo_doc['template_ids'] = [
            mapping_tables['template'].get(str(tid))
            for tid in mongo_doc['template_ids']
        ]
    
    return mongo_doc
```

### 3.3 Foreign Key Reference Map

All foreign key relationships that need ID conversion:

#### Cycles Table
- `subscription_id` → subscriptions(id)

#### Subscriptions Table
- `customer_id` → Keep as string (out of scope) or convert if migrating customers
- `sending_profile_id` → Keep as string (out of scope)
- `landing_page_id` → Keep as string (out of scope)

#### Primary Contacts Table
- `subscription_id` → subscriptions(id)

#### Targets Table
- `cycle_id` → cycles(id)
- `subscription_id` → subscriptions(id)
- `template_id` → templates(id)

#### Target Timeline Events Table
- `target_id` → targets(id)

#### Subscription Tasks Table
- `subscription_id` → subscriptions(id)

#### Subscription Notification History Table
- `subscription_id` → subscriptions(id)

#### Subscription Test Results Table
- `subscription_id` → subscriptions(id)
- `template_id` → templates(id)

#### Test Timeline Events Table
- `test_result_id` → subscription_test_results(id)

## 4. Application Code Changes

### 4.1 con-pca-tasks (Go) Changes

#### Current Pattern:
```go
// cycles.go
func GetCycle(id string) (Cycle, error) {
    objectId, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        return Cycle{}, err
    }
    var c Cycle
    err = db.CycleCollection.FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).Decode(&c)
    return c, err
}
```

#### PostgreSQL Pattern:
```go
// cycles.go
func GetCycle(id string) (Cycle, error) {
    // Validate UUID format
    _, err := uuid.Parse(id)
    if err != nil {
        return Cycle{}, fmt.Errorf("invalid UUID: %w", err)
    }
    
    var c Cycle
    query := "SELECT * FROM cycles WHERE id = $1"
    err = db.QueryRow(query, id).Scan(
        &c.ID,
        &c.SubscriptionID,
        // ... other fields
    )
    return c, err
}
```

### 4.2 con-pca-api (Python) Changes

#### Current Pattern:
```python
# manager.py
def document_query(self, document_id):
    if type(document_id) is str:
        return {"_id": ObjectId(document_id)}
    elif type(document_id) is ObjectId:
        return {"_id": document_id}
```

#### PostgreSQL Pattern:
```python
# manager.py (PostgreSQL version)
def document_query(self, document_id):
    """
    Get query for a document by UUID.
    In PostgreSQL, UUIDs can be passed as strings.
    """
    if isinstance(document_id, str):
        # Validate UUID format
        try:
            uuid.UUID(document_id)
            return {"id": document_id}
        except ValueError:
            raise ValueError(f"Invalid UUID: {document_id}")
    elif isinstance(document_id, uuid.UUID):
        return {"id": str(document_id)}
    else:
        raise TypeError(f"document_id must be string or UUID, got {type(document_id)}")
```

## 5. HTTP Endpoint Compatibility

### 5.1 Current Endpoint Behavior

```bash
# Request with MongoDB ObjectID
GET /api/v1/cycles/507f1f77bcf86cd799439011

# Response
{
  "_id": "507f1f77bcf86cd799439011",
  "subscription_id": "507f191e810c19729de860ea",
  ...
}
```

### 5.2 PostgreSQL Endpoint Behavior

```bash
# Request with UUID
GET /api/v1/cycles/550e8400-e29b-41d4-a716-446655440000

# Response
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "subscription_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  ...
}
```

### 5.3 Breaking Changes

1. **ID Length Change:** 24 chars → 36 chars
   - Client validation code may need updates
   - Database field lengths in client-side storage

2. **ID Format Change:** Hex only → Hex with hyphens
   - Regular expressions for ID validation need updates
   - URL encoding remains unchanged (hyphens don't need encoding)

3. **Field Name Change:** `_id` → `id`
   - JSON parsing code needs updates
   - ORM/Schema definitions need updates

### 5.4 Mitigation Strategy

**Option 1: API Version Bump**
```
/api/v2/cycles/{uuid}  # New PostgreSQL version
/api/v1/cycles/{objectid}  # Legacy MongoDB version (read-only)
```

**Option 2: Accept Both Formats During Transition**
```python
@app.route('/api/v1/cycles/<cycle_id>')
def get_cycle(cycle_id):
    if len(cycle_id) == 24:
        # MongoDB ObjectID - look up in mapping table
        pg_id = get_postgres_id_from_mapping('cycle', cycle_id)
        cycle = get_cycle_from_postgres(pg_id)
    elif len(cycle_id) == 36:
        # PostgreSQL UUID
        cycle = get_cycle_from_postgres(cycle_id)
    else:
        return {"error": "Invalid ID format"}, 400
    
    return jsonify(cycle)
```

**Recommendation:** Use Option 2 during transition, then deprecate MongoDB ID support after migration complete.

## 6. Data Migration Script Outline

```python
#!/usr/bin/env python3
"""
MongoDB to PostgreSQL ID Migration Script
"""

import uuid
from pymongo import MongoClient
import psycopg2
from psycopg2.extras import execute_batch

class IDMigrationOrchestrator:
    def __init__(self, mongo_uri, postgres_uri):
        self.mongo = MongoClient(mongo_uri)
        self.pg = psycopg2.connect(postgres_uri)
        self.mappings = {}
    
    def migrate_all(self):
        """Execute full migration in correct order"""
        # Phase 1: Independent collections
        self.migrate_templates()
        self.migrate_notifications()
        
        # Phase 2: Subscriptions
        self.migrate_subscriptions()
        self.migrate_primary_contacts()
        self.migrate_subscription_tasks()
        
        # Phase 3: Cycles
        self.migrate_cycles()
        
        # Phase 4: Targets
        self.migrate_targets()
        self.migrate_target_timeline()
        
        # Phase 5: Test results
        self.migrate_test_results()
        self.migrate_test_timeline()
        
        # Phase 6: Notification history
        self.migrate_notification_history()
    
    def migrate_templates(self):
        """Migrate template collection"""
        print("Migrating templates...")
        collection = self.mongo.conpca.template
        self.mappings['template'] = {}
        
        cursor = self.pg.cursor()
        
        for doc in collection.find():
            # Generate new UUID
            pg_id = str(uuid.uuid4())
            mongo_id = str(doc['_id'])
            
            # Store mapping
            self.mappings['template'][mongo_id] = pg_id
            cursor.execute("""
                INSERT INTO id_migration_mapping 
                (collection_name, mongodb_id, postgres_id)
                VALUES (%s, %s, %s)
            """, ('template', mongo_id, pg_id))
            
            # Insert template with new UUID
            cursor.execute("""
                INSERT INTO templates (
                    id, name, subject, html, text, retired, 
                    deception_score, from_address, indicators
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                pg_id,
                doc.get('name'),
                doc.get('subject'),
                doc.get('html'),
                doc.get('text'),
                doc.get('retired', False),
                doc.get('deception_score'),
                doc.get('from_address'),
                json.dumps(doc.get('indicators', {}))
            ))
        
        self.pg.commit()
        print(f"Migrated {len(self.mappings['template'])} templates")
    
    # ... similar methods for other collections

def main():
    migrator = IDMigrationOrchestrator(
        mongo_uri="mongodb://localhost:27017",
        postgres_uri="postgresql://user:pass@localhost:5432/conpca"
    )
    
    try:
        migrator.migrate_all()
        print("Migration completed successfully!")
    except Exception as e:
        print(f"Migration failed: {e}")
        migrator.pg.rollback()
        raise

if __name__ == '__main__':
    main()
```

## 7. Testing Strategy

### 7.1 Pre-Migration Tests

```python
def test_id_generation():
    """Verify UUID generation works"""
    cursor.execute("SELECT gen_random_uuid()")
    uuid_value = cursor.fetchone()[0]
    assert len(str(uuid_value)) == 36
    assert str(uuid_value).count('-') == 4

def test_foreign_key_constraints():
    """Verify FK constraints are properly defined"""
    # Try inserting cycle with non-existent subscription_id
    with pytest.raises(psycopg2.IntegrityError):
        cursor.execute("""
            INSERT INTO cycles (id, subscription_id, start_date, end_date)
            VALUES (gen_random_uuid(), gen_random_uuid(), NOW(), NOW())
        """)
```

### 7.2 Migration Validation Tests

```python
def test_record_counts():
    """Verify all records migrated"""
    mongo_count = mongo.conpca.cycle.count_documents({})
    cursor.execute("SELECT COUNT(*) FROM cycles")
    pg_count = cursor.fetchone()[0]
    assert mongo_count == pg_count

def test_foreign_key_integrity():
    """Verify all FKs resolved correctly"""
    # Check for null FKs where they shouldn't be
    cursor.execute("""
        SELECT COUNT(*) FROM cycles WHERE subscription_id IS NULL
    """)
    assert cursor.fetchone()[0] == 0
    
    # Check for broken FKs
    cursor.execute("""
        SELECT COUNT(*) 
        FROM cycles c 
        LEFT JOIN subscriptions s ON c.subscription_id = s.id 
        WHERE s.id IS NULL
    """)
    assert cursor.fetchone()[0] == 0

def test_mapping_completeness():
    """Verify all IDs have mappings"""
    cursor.execute("""
        SELECT collection_name, COUNT(*) 
        FROM id_migration_mapping 
        GROUP BY collection_name
    """)
    mappings = dict(cursor.fetchall())
    
    # Verify counts match
    assert mappings['cycle'] == mongo.conpca.cycle.count_documents({})
    assert mappings['subscription'] == mongo.conpca.subscription.count_documents({})
```

### 7.3 Post-Migration API Tests

```python
def test_api_with_uuid():
    """Test API endpoints with UUIDs"""
    # Get a UUID from database
    cursor.execute("SELECT id FROM cycles LIMIT 1")
    cycle_id = cursor.fetchone()[0]
    
    # Test API endpoint
    response = requests.get(f"http://api/v1/cycles/{cycle_id}")
    assert response.status_code == 200
    assert response.json()['id'] == str(cycle_id)

def test_api_with_legacy_objectid():
    """Test API handles legacy ObjectIDs during transition"""
    # Get mapping
    cursor.execute("""
        SELECT mongodb_id, postgres_id 
        FROM id_migration_mapping 
        WHERE collection_name = 'cycle' 
        LIMIT 1
    """)
    mongo_id, pg_id = cursor.fetchone()
    
    # Test with legacy ID
    response = requests.get(f"http://api/v1/cycles/{mongo_id}")
    assert response.status_code == 200
    assert response.json()['id'] == str(pg_id)
```

## 8. Cleanup After Migration

Once migration is complete and validated:

```sql
-- Remove temporary mapping table
DROP TABLE id_migration_mapping;

-- Remove any transition code from application
-- Remove MongoDB ID compatibility layer from API
```

## 9. Recommendations

### 9.1 Immediate Actions

1. ✅ Use `UUID` type with `gen_random_uuid()` for all new PostgreSQL tables
2. ✅ Create `id_migration_mapping` table for transition period
3. ✅ Plan API versioning or compatibility layer for ID format change
4. ✅ Update client documentation with new ID format

### 9.2 Migration Timeline

1. **Week 1:** Create migration scripts and test on development data
2. **Week 2:** Run migration in staging environment
3. **Week 3:** Validate all foreign key relationships and run API tests
4. **Week 4:** Deploy with dual-ID support (MongoDB + PostgreSQL)
5. **Week 5+:** Monitor, fix issues, deprecate MongoDB ID support

### 9.3 Rollback Plan

Maintain `id_migration_mapping` table for at least 30 days post-migration to enable:
- Looking up old ObjectIDs from new UUIDs
- Rolling back to MongoDB if critical issues found
- Debugging reference issues

## 10. Conclusion

**Key Takeaways:**

1. ✅ **No Direct Conversion:** MongoDB ObjectIDs and PostgreSQL UUIDs are incompatible formats
2. ✅ **Mapping Required:** Temporary mapping table enables reference preservation
3. ✅ **HTTP Compatibility:** String-based IDs in API make format change transparent
4. ⚠️ **Client Updates:** Clients may need updates for ID length/format validation
5. ✅ **Migration Path:** Clear sequence preserves data integrity through FK constraints

The migration strategy ensures zero data loss while leveraging PostgreSQL's native UUID support for future scalability and standard compliance.

---

**Prepared by:** Devin AI  
**Session:** https://app.devin.ai/sessions/df7340be39754e4088080fa2b29c0e41  
**Date:** October 8, 2025
