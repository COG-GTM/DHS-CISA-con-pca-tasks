# Database Connection Refactoring Plan - MongoDB to PostgreSQL

**Ticket:** MBA-322 - Phase 1 Database Schema Design for PostgreSQL Migration  
**Repository:** COG-GTM/DHS-CISA-con-pca-tasks  
**Analysis Date:** October 8, 2025  
**Analyst:** Devin AI

---

## Executive Summary

This document provides a comprehensive plan for refactoring the database connection layer from MongoDB to PostgreSQL, maintaining the same initialization patterns and global access patterns while adapting to PostgreSQL's connection pooling and query paradigms.

---

## Current MongoDB Implementation

### File Structure

```
database/
├── mongo.go                    # Connection and initialization
└── collections/
    ├── cycles.go              # Cycle queries
    ├── subscriptions.go       # Subscription queries
    ├── notifications.go       # Notification queries
    └── phishes.go             # Template queries
```

### Current Connection Implementation

**File:** `database/mongo.go`

```go
package database

import (
    "context"
    "os"
    "time"
    
    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"
    "go.mongodb.org/mongo-driver/mongo/readpref"
)

var (
    Ctx                     = context.Background()
    NotificationsCollection *mongo.Collection
    PhishesCollection       *mongo.Collection
    SubscriptionsCollection *mongo.Collection
    CyclesCollection        *mongo.Collection
)

func connect() (*mongo.Client, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    client, err := mongo.Connect(ctx, options.Client().ApplyURI(os.Getenv("MONGO_URI")))
    if err != nil {
        return nil, err
    }
    
    ctx, cancel = context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()
    err = client.Ping(ctx, readpref.Primary())
    if err != nil {
        return nil, err
    }
    
    return client, nil
}

// InitDB initializes database connection and sets the collections
func InitDB() {
    client, err := connect()
    if err != nil {
        panic(err)
    }
    db := client.Database("pca")
    
    // Set the collections
    CyclesCollection = db.Collection("cycle")
    NotificationsCollection = db.Collection("notification")
    PhishesCollection = db.Collection("template")
    SubscriptionsCollection = db.Collection("subscription")
}
```

### Key Characteristics

1. **Fail-Fast Pattern:** `panic(err)` if connection fails during initialization
2. **Global Variables:** Collections exposed as package-level variables
3. **Environment Configuration:** Connection string from `MONGO_URI` environment variable
4. **Timeout Handling:** 10s connection timeout, 2s ping timeout
5. **Single Database:** "pca" database name hardcoded
6. **No Connection Pooling Logic:** MongoDB driver handles pooling internally

### Current Usage Pattern

**Initialization:** `initialize.go` calls `database.InitDB()`

**Query Pattern:** Direct access to global collection variables
```go
err := db.CyclesCollection.
    FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).
    Decode(&c)
```

---

## PostgreSQL Target Implementation

### Recommended File Structure

```
database/
├── postgres.go                 # Connection and initialization (replaces mongo.go)
├── models/                     # Data models (new)
│   ├── cycle.go
│   ├── subscription.go
│   ├── notification.go
│   └── template.go
└── repositories/               # Query functions (replaces collections/)
    ├── cycles.go
    ├── subscriptions.go
    ├── notifications.go
    └── templates.go
```

### PostgreSQL Connection Implementation

**File:** `database/postgres.go` (new file, replaces mongo.go)

```go
package database

import (
    "context"
    "database/sql"
    "fmt"
    "os"
    "time"
    
    "github.com/jmoiron/sqlx"
    _ "github.com/lib/pq"
)

// Global variables - maintain same pattern as MongoDB
var (
    Ctx context.Context
    DB  *sqlx.DB
)

// Connection configuration
type Config struct {
    Host            string
    Port            string
    User            string
    Password        string
    Database        string
    SSLMode         string
    MaxOpenConns    int
    MaxIdleConns    int
    ConnMaxLifetime time.Duration
}

// getConfigFromEnv reads configuration from environment variables
func getConfigFromEnv() Config {
    return Config{
        Host:            getEnvOrDefault("POSTGRES_HOST", "localhost"),
        Port:            getEnvOrDefault("POSTGRES_PORT", "5432"),
        User:            getEnvOrDefault("POSTGRES_USER", "pca_user"),
        Password:        os.Getenv("POSTGRES_PASSWORD"), // Required, no default
        Database:        getEnvOrDefault("POSTGRES_DB", "pca"),
        SSLMode:         getEnvOrDefault("POSTGRES_SSLMODE", "require"),
        MaxOpenConns:    25,  // Configurable via env if needed
        MaxIdleConns:    5,
        ConnMaxLifetime: 5 * time.Minute,
    }
}

func getEnvOrDefault(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

// buildConnectionString creates PostgreSQL connection string
func buildConnectionString(cfg Config) string {
    return fmt.Sprintf(
        "host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
        cfg.Host,
        cfg.Port,
        cfg.User,
        cfg.Password,
        cfg.Database,
        cfg.SSLMode,
    )
}

// connect establishes PostgreSQL connection with retries
func connect() (*sqlx.DB, error) {
    cfg := getConfigFromEnv()
    
    // Validate required configuration
    if cfg.Password == "" {
        return nil, fmt.Errorf("POSTGRES_PASSWORD environment variable is required")
    }
    
    connStr := buildConnectionString(cfg)
    
    // Create context with timeout (matches MongoDB 10s timeout)
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    // Open connection
    db, err := sqlx.ConnectContext(ctx, "postgres", connStr)
    if err != nil {
        return nil, fmt.Errorf("failed to connect to database: %w", err)
    }
    
    // Configure connection pool
    db.SetMaxOpenConns(cfg.MaxOpenConns)
    db.SetMaxIdleConns(cfg.MaxIdleConns)
    db.SetConnMaxLifetime(cfg.ConnMaxLifetime)
    
    // Verify connection (matches MongoDB ping with 2s timeout)
    pingCtx, pingCancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer pingCancel()
    
    if err := db.PingContext(pingCtx); err != nil {
        db.Close()
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }
    
    return db, nil
}

// InitDB initializes database connection - maintains same signature as MongoDB version
func InitDB() {
    var err error
    
    // Create global context
    Ctx = context.Background()
    
    // Establish connection
    DB, err = connect()
    if err != nil {
        // Maintain fail-fast pattern from MongoDB implementation
        panic(fmt.Sprintf("Database initialization failed: %v", err))
    }
    
    // Optional: Run migrations or verify schema
    // if err := verifySchema(); err != nil {
    //     panic(fmt.Sprintf("Schema verification failed: %v", err))
    // }
}

// Close gracefully closes the database connection
func Close() error {
    if DB != nil {
        return DB.Close()
    }
    return nil
}

// Health check for monitoring
func HealthCheck() error {
    if DB == nil {
        return fmt.Errorf("database not initialized")
    }
    
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()
    
    return DB.PingContext(ctx)
}
```

### Environment Variable Mapping

| MongoDB | PostgreSQL | Default | Notes |
|---------|------------|---------|-------|
| `MONGO_URI` | `POSTGRES_HOST` | localhost | Hostname |
| | `POSTGRES_PORT` | 5432 | Port number |
| | `POSTGRES_USER` | pca_user | Database user |
| | `POSTGRES_PASSWORD` | (required) | Database password |
| | `POSTGRES_DB` | pca | Database name |
| | `POSTGRES_SSLMODE` | require | SSL mode |

**Example .env configuration:**
```bash
# PostgreSQL Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=pca_user
POSTGRES_PASSWORD=secure_password_here
POSTGRES_DB=pca
POSTGRES_SSLMODE=require
```

---

## Query Layer Refactoring

### Current MongoDB Pattern

**File:** `database/collections/cycles.go`

```go
package collections

import (
    db "github.com/cisagov/con-pca-tasks/database"
    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/bson/primitive"
)

type Cycle struct {
    SubscriptionId string `bson:"subscription_id"`
    // ... other fields
}

func GetCycle(id string) (Cycle, error) {
    var c Cycle
    objectId, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        return c, err
    }
    err = db.CyclesCollection.
        FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).
        Decode(&c)
    return c, err
}
```

### PostgreSQL Pattern

**File:** `database/models/cycle.go` (new)

```go
package models

import (
    "time"
    "github.com/google/uuid"
)

type Cycle struct {
    ID             uuid.UUID  `db:"id" json:"id"`
    LegacyObjectID *string    `db:"legacy_objectid" json:"legacy_objectid,omitempty"`
    SubscriptionID uuid.UUID  `db:"subscription_id" json:"subscription_id"`
    TemplateIDs    []byte     `db:"template_ids" json:"template_ids"` // JSONB stored as []byte
    StartDate      time.Time  `db:"start_date" json:"start_date"`
    EndDate        time.Time  `db:"end_date" json:"end_date"`
    SendByDate     time.Time  `db:"send_by_date" json:"send_by_date"`
    Active         bool       `db:"active" json:"active"`
    TargetCount    int        `db:"target_count" json:"target_count"`
    CreatedAt      time.Time  `db:"created_at" json:"created_at"`
    UpdatedAt      time.Time  `db:"updated_at" json:"updated_at"`
}
```

**File:** `database/repositories/cycles.go` (replaces collections/cycles.go)

```go
package repositories

import (
    "database/sql"
    "fmt"
    
    "github.com/google/uuid"
    db "github.com/cisagov/con-pca-tasks/database"
    "github.com/cisagov/con-pca-tasks/database/models"
)

// GetCycle retrieves a cycle by ID (supports both UUID and legacy ObjectID)
func GetCycle(id string) (models.Cycle, error) {
    var c models.Cycle
    
    // Try to parse as UUID first
    parsedUUID, err := uuid.Parse(id)
    if err == nil {
        // Query by UUID (primary key)
        query := `
            SELECT id, legacy_objectid, subscription_id, template_ids,
                   start_date, end_date, send_by_date, active, target_count,
                   created_at, updated_at
            FROM cycles
            WHERE id = $1
        `
        err = db.DB.GetContext(db.Ctx, &c, query, parsedUUID)
        if err == nil {
            return c, nil
        }
        if err != sql.ErrNoRows {
            return c, fmt.Errorf("query by UUID failed: %w", err)
        }
    }
    
    // Fallback: try legacy ObjectID (24-char hex string)
    if len(id) == 24 && isHexString(id) {
        query := `
            SELECT id, legacy_objectid, subscription_id, template_ids,
                   start_date, end_date, send_by_date, active, target_count,
                   created_at, updated_at
            FROM cycles
            WHERE legacy_objectid = $1
        `
        err = db.DB.GetContext(db.Ctx, &c, query, id)
        if err != nil {
            return c, fmt.Errorf("query by legacy ID failed: %w", err)
        }
        return c, nil
    }
    
    return c, fmt.Errorf("invalid ID format: must be UUID or 24-char hex string")
}

// isHexString validates if a string contains only hex characters
func isHexString(s string) bool {
    for _, c := range s {
        if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
            return false
        }
    }
    return true
}

// GetCyclesBySubscription retrieves all cycles for a subscription
func GetCyclesBySubscription(subscriptionID uuid.UUID) ([]models.Cycle, error) {
    var cycles []models.Cycle
    
    query := `
        SELECT id, legacy_objectid, subscription_id, template_ids,
               start_date, end_date, send_by_date, active, target_count,
               created_at, updated_at
        FROM cycles
        WHERE subscription_id = $1
        ORDER BY start_date DESC
    `
    
    err := db.DB.SelectContext(db.Ctx, &cycles, query, subscriptionID)
    if err != nil {
        return nil, fmt.Errorf("failed to get cycles by subscription: %w", err)
    }
    
    return cycles, nil
}

// GetActiveCycles retrieves all active cycles
func GetActiveCycles() ([]models.Cycle, error) {
    var cycles []models.Cycle
    
    query := `
        SELECT id, legacy_objectid, subscription_id, template_ids,
               start_date, end_date, send_by_date, active, target_count,
               created_at, updated_at
        FROM cycles
        WHERE active = true
        ORDER BY start_date ASC
    `
    
    err := db.DB.SelectContext(db.Ctx, &cycles, query)
    if err != nil {
        return nil, fmt.Errorf("failed to get active cycles: %w", err)
    }
    
    return cycles, nil
}
```

---

## Migration Comparison

### Side-by-Side Comparison

| Aspect | MongoDB Implementation | PostgreSQL Implementation |
|--------|------------------------|---------------------------|
| **Connection** | `mongo.Connect()` | `sqlx.ConnectContext()` |
| **Driver** | `go.mongodb.org/mongo-driver/mongo` | `github.com/lib/pq` + `github.com/jmoiron/sqlx` |
| **Global Access** | `db.CyclesCollection` | `db.DB` |
| **Context** | `db.Ctx` (global) | `db.Ctx` (global, same) |
| **Init Function** | `InitDB()` - panic on fail | `InitDB()` - panic on fail (same) |
| **Env Config** | `MONGO_URI` | Multiple `POSTGRES_*` vars |
| **Timeout** | 10s connect, 2s ping | 10s connect, 2s ping (same) |
| **Query Pattern** | `FindOne().Decode()` | `GetContext()` with SQL |
| **Models** | Inline in collection files | Separate `models/` package |
| **Fail-Fast** | ✅ Yes | ✅ Yes (maintained) |

---

## Connection Pooling Strategy

### MongoDB Connection Pooling

MongoDB driver handles pooling automatically:
- Default pool size: 100 connections
- No explicit configuration in current code
- Managed internally by driver

### PostgreSQL Connection Pooling

PostgreSQL requires explicit pool configuration:

```go
db.SetMaxOpenConns(25)     // Maximum open connections
db.SetMaxIdleConns(5)      // Maximum idle connections in pool
db.SetConnMaxLifetime(5 * time.Minute)  // Maximum lifetime of connection
```

**Recommended Settings for con-pca-tasks:**

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| MaxOpenConns | 25 | Matches expected concurrency (task scheduler) |
| MaxIdleConns | 5 | Keep connections warm for periodic tasks |
| ConnMaxLifetime | 5 minutes | Balance between reuse and freshness |

**Production Tuning:**
- Monitor connection usage metrics
- Adjust based on actual concurrent task execution
- Consider higher limits for high-load periods

---

## Dependency Changes

### Remove MongoDB Dependencies

```go
// Remove from go.mod
- go.mongodb.org/mongo-driver v1.x.x
```

### Add PostgreSQL Dependencies

```go
// Add to go.mod
+ github.com/lib/pq v1.10.9              // PostgreSQL driver
+ github.com/jmoiron/sqlx v1.3.5         // SQL extensions
+ github.com/google/uuid v1.5.0          // UUID support
```

**Installation:**
```bash
go get github.com/lib/pq@v1.10.9
go get github.com/jmoiron/sqlx@v1.3.5
go get github.com/google/uuid@v1.5.0
go mod tidy
```

---

## Testing Strategy

### Unit Tests

**File:** `database/postgres_test.go` (new)

```go
package database

import (
    "os"
    "testing"
    
    "github.com/stretchr/testify/assert"
)

func TestGetConfigFromEnv(t *testing.T) {
    // Set test environment variables
    os.Setenv("POSTGRES_HOST", "testhost")
    os.Setenv("POSTGRES_PASSWORD", "testpass")
    defer os.Clearenv()
    
    cfg := getConfigFromEnv()
    assert.Equal(t, "testhost", cfg.Host)
    assert.Equal(t, "testpass", cfg.Password)
    assert.Equal(t, "5432", cfg.Port) // Default
}

func TestBuildConnectionString(t *testing.T) {
    cfg := Config{
        Host:     "localhost",
        Port:     "5432",
        User:     "testuser",
        Password: "testpass",
        Database: "testdb",
        SSLMode:  "disable",
    }
    
    expected := "host=localhost port=5432 user=testuser password=testpass dbname=testdb sslmode=disable"
    actual := buildConnectionString(cfg)
    assert.Equal(t, expected, actual)
}
```

### Integration Tests

```go
func TestInitDB_Success(t *testing.T) {
    // Requires test PostgreSQL instance
    if testing.Short() {
        t.Skip("Skipping integration test")
    }
    
    // Set test environment
    os.Setenv("POSTGRES_HOST", "localhost")
    os.Setenv("POSTGRES_PASSWORD", "testpass")
    defer os.Clearenv()
    
    // Should not panic
    assert.NotPanics(t, func() {
        InitDB()
    })
    
    // Verify connection
    assert.NotNil(t, DB)
    assert.NoError(t, HealthCheck())
    
    // Cleanup
    Close()
}
```

---

## Migration Checklist

### Phase 1: Prepare PostgreSQL Connection

- [ ] Create `database/postgres.go` with connection logic
- [ ] Add PostgreSQL dependencies to `go.mod`
- [ ] Create environment variable documentation
- [ ] Implement connection pooling configuration
- [ ] Add health check endpoint

### Phase 2: Refactor Data Models

- [ ] Create `database/models/` directory
- [ ] Define `Cycle` model with UUID support
- [ ] Define `Subscription` model
- [ ] Define `Notification` model
- [ ] Define `Template` model
- [ ] Add dual ID support (UUID + legacy ObjectID)

### Phase 3: Refactor Query Layer

- [ ] Create `database/repositories/` directory
- [ ] Migrate `GetCycle()` to PostgreSQL
- [ ] Migrate `GetSubscription()` to PostgreSQL
- [ ] Migrate `GetNotification()` to PostgreSQL
- [ ] Migrate `GetPhish()` to PostgreSQL
- [ ] Add backward compatibility for ObjectID lookup

### Phase 4: Update Application Code

- [ ] Update imports from `collections` to `repositories`
- [ ] Test `notifications/manager.go` with PostgreSQL
- [ ] Test HTTP endpoints with UUID and ObjectID
- [ ] Update error handling for SQL-specific errors

### Phase 5: Testing

- [ ] Unit tests for connection logic
- [ ] Integration tests with test database
- [ ] Load tests for connection pooling
- [ ] Backward compatibility tests with ObjectID

### Phase 6: Deployment

- [ ] Configure production PostgreSQL instance
- [ ] Set production environment variables
- [ ] Run database migrations
- [ ] Deploy updated application
- [ ] Monitor connection pool metrics

---

## Rollback Plan

### Quick Rollback (If PostgreSQL Issues Found)

1. **Keep MongoDB Connection Code**
   - Don't delete `database/mongo.go` during initial deployment
   - Use feature flag to switch between MongoDB and PostgreSQL

```go
// Feature flag approach
func InitDB() {
    if os.Getenv("USE_POSTGRES") == "true" {
        initPostgreSQL()
    } else {
        initMongoDB()
    }
}
```

2. **Dual-Write Pattern (Optional)**
   - Write to both databases during transition
   - Read from PostgreSQL, fallback to MongoDB
   - Allows gradual migration with safety net

---

## Performance Considerations

### Connection Pool Monitoring

Add metrics for:
- Active connections
- Idle connections
- Wait time for connections
- Query execution time

**Example Monitoring:**
```go
func GetPoolStats() {
    stats := DB.Stats()
    log.Printf("Open connections: %d", stats.OpenConnections)
    log.Printf("In use: %d", stats.InUse)
    log.Printf("Idle: %d", stats.Idle)
    log.Printf("Wait count: %d", stats.WaitCount)
    log.Printf("Wait duration: %v", stats.WaitDuration)
}
```

### Query Performance

- Use `EXPLAIN ANALYZE` for slow queries
- Monitor query execution times
- Add database query logging in development
- Consider prepared statements for frequently-used queries

---

## Security Considerations

### Connection Security

1. **SSL/TLS Encryption**
   - Default: `sslmode=require`
   - Production: `sslmode=verify-full` with CA certificate

2. **Password Management**
   - Never hardcode passwords
   - Use environment variables or secrets manager
   - Rotate credentials periodically

3. **Least Privilege**
   - Create database user with minimal required permissions
   - Read-only for con-pca-tasks (no write operations found)

**Example SQL for user creation:**
```sql
CREATE USER pca_tasks_user WITH PASSWORD 'secure_password';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO pca_tasks_user;
GRANT USAGE ON SCHEMA public TO pca_tasks_user;
```

---

## Conclusion

This refactoring plan maintains the same initialization patterns and fail-fast behavior as the current MongoDB implementation while adapting to PostgreSQL's connection pooling requirements and SQL query patterns.

**Key Principles:**
1. ✅ Maintain global access pattern
2. ✅ Keep fail-fast initialization
3. ✅ Preserve environment configuration approach
4. ✅ Add explicit connection pooling
5. ✅ Support backward compatibility with ObjectIDs

**Next Steps:**
1. Implement `database/postgres.go`
2. Create data models in `database/models/`
3. Refactor queries in `database/repositories/`
4. Test with local PostgreSQL instance
5. Deploy to staging environment

---

**Document Version:** 1.0  
**Status:** IMPLEMENTATION READY  
**Estimated Effort:** 2-3 developer days for initial implementation + 1 day testing
