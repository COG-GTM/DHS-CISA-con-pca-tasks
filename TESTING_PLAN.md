# Comprehensive Testing Plan for con-pca-tasks

## Executive Summary

This document outlines a comprehensive testing strategy for the `COG-GTM/DHS-CISA-con-pca-tasks` repository. The current test coverage is minimal (12.5% for controllers, 19.4% for AWS services, 0% for all other packages). This plan establishes a roadmap to achieve comprehensive test coverage across all components.

## Current State Analysis

### Existing Test Coverage

**Baseline Coverage (as of initial analysis):**
```
Package                                          Coverage
-------------------------------------------------------------
github.com/cisagov/con-pca-tasks                 0.0%
github.com/cisagov/con-pca-tasks/notifications   0.0%
github.com/cisagov/con-pca-tasks/database        0.0%
github.com/cisagov/con-pca-tasks/services/mailgun 0.0%
github.com/cisagov/con-pca-tasks/database/collections 0.0%
github.com/cisagov/con-pca-tasks/controllers     12.5%
github.com/cisagov/con-pca-tasks/services/aws    19.4%
```

**Overall Coverage: ~5%**

### Existing Tests

1. **controllers/controllers_test.go**
   - `TestHealthCheckHandler` - Tests the health check endpoint (✓ Active)
   - `TestEmailReportHandler` - Commented out due to mocking complexity (✗ Inactive)

2. **services/aws/sts_test.go**
   - `TestAssumedRoleConfig` - Tests AWS STS role assumption configuration (✓ Active)

### Components Without Tests

1. **Main Package** (`main.go`, `initialize.go`, `version.go`)
   - HTTP server initialization
   - Auth middleware
   - Application initialization

2. **Controllers** (`controllers/controllers.go`)
   - `emailReportHandler` - Email report endpoint (commented test exists)
   - `pdfReportHandler` - PDF report endpoint (no test)
   - `TasksRouter` - Route configuration (no test)

3. **Notifications** (`notifications/`)
   - `Manager` - Core email workflow orchestration (no test)
   - `generatePDF` - PDF generation from API (no test)
   - `Template.Render` - Go template rendering (no test)

4. **Database** (`database/`)
   - `InitDB` - Database initialization (no test)
   - `connect` - MongoDB connection (no test)

5. **Database Collections** (`database/collections/`)
   - `GetCycle` - Cycle retrieval (no test)
   - `GetNotification` - Notification template retrieval (no test)
   - `GetSubscription` - Subscription retrieval (no test)

6. **AWS Services** (`services/aws/`)
   - `SESEmailClient` - SES client initialization (no test)
   - `NewSESEmail` - Email context creation (no test)
   - `SESEmail.BuildMessage` - Email message construction (no test)
   - `SESEmail.Send` - Email sending via SES (no test)

7. **Mailgun Services** (`services/mailgun/`)
   - `MailgunEmail.BuildMessage` - Email message construction (no test)
   - `MailgunEmail.Send` - Email sending via Mailgun (no test)

## Testing Strategy

### Test Categories

We will implement three categories of tests:

1. **Unit Tests** - Test individual functions and methods in isolation with mocked dependencies
2. **Integration Tests** - Test component interactions with real or containerized dependencies
3. **E2E Tests** - Test complete workflows from HTTP request to response

### Technology Stack

- **Testing Framework**: Go's built-in `testing` package
- **Mocking**: 
  - `github.com/stretchr/testify/mock` - For creating mocks
  - `github.com/stretchr/testify/assert` - For assertions
- **MongoDB Testing**: `github.com/testcontainers/testcontainers-go` - For containerized MongoDB in integration tests
- **HTTP Testing**: `net/http/httptest` - For HTTP endpoint testing
- **Coverage Tools**: Go's built-in coverage tools (`go test -cover`, `go tool cover`)
- **E2E Testing**: Custom Go-based E2E tests using real HTTP clients

## Implementation Plan

### Priority 1: Unit Tests for Core Components (HIGH)

These tests provide the foundation and catch most bugs during development.

#### 1.1 Controllers Package (`controllers/`)

**Files to Create:**
- `controllers/controllers_test.go` (enhance existing)

**Tests to Implement:**

| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestHealthCheckHandler` | Health check endpoint (✓ exists) | None |
| `TestEmailReportHandler` | Email report handler with valid params | `notifications.Manager` |
| `TestEmailReportHandler_InvalidCycleID` | Email handler with invalid cycle ID | `notifications.Manager` |
| `TestPdfReportHandler` | PDF report handler with valid params | None |
| `TestPdfReportHandler_InvalidParams` | PDF handler with invalid params | None |
| `TestTasksRouter` | Route configuration and path matching | None |
| `TestTasksRouter_MethodNotAllowed` | Invalid HTTP methods | None |

**Estimated Coverage Target:** 90%+

#### 1.2 Notifications Package (`notifications/`)

**Files to Create:**
- `notifications/manager_test.go`
- `notifications/template_test.go`

**Tests to Implement:**

**manager_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestManager_Success` | Complete email workflow | MongoDB, AWS SES, HTTP API |
| `TestManager_CycleNotFound` | Handle cycle retrieval failure | MongoDB |
| `TestManager_SubscriptionNotFound` | Handle subscription retrieval failure | MongoDB |
| `TestManager_NotificationNotFound` | Handle notification retrieval failure | MongoDB |
| `TestManager_PDFGenerationFailure` | Handle PDF API failure | HTTP API |
| `TestManager_EmailSendFailure` | Handle SES send failure | AWS SES |
| `TestGeneratePDF_Success` | PDF generation from API | HTTP API |
| `TestGeneratePDF_APIError` | API returns error | HTTP API |
| `TestGeneratePDF_FileWriteError` | File system error | File system |

**template_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestTemplate_Render_ValidTemplate` | Render template with valid data | None |
| `TestTemplate_Render_EmptyTemplate` | Render empty template | None |
| `TestTemplate_Render_InvalidTemplate` | Handle template parse error | None |
| `TestTemplate_Render_WithVariables` | Substitute FirstName/LastName | None |
| `TestTemplate_Render_HTMLEscaping` | Ensure proper HTML escaping | None |

**Estimated Coverage Target:** 85%+

#### 1.3 Database Package (`database/`)

**Files to Create:**
- `database/mongo_test.go`

**Tests to Implement:**

| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestConnect_Success` | Successful MongoDB connection | Mock MongoDB |
| `TestConnect_InvalidURI` | Invalid connection URI | Mock MongoDB |
| `TestConnect_ConnectionTimeout` | Connection timeout | Mock MongoDB |
| `TestConnect_PingFailure` | Ping fails after connection | Mock MongoDB |
| `TestInitDB_Success` | Initialize collections successfully | Mock MongoDB |
| `TestInitDB_ConnectionFailure` | Handle connection failure | Mock MongoDB |

**Estimated Coverage Target:** 80%+

#### 1.4 Database Collections Package (`database/collections/`)

**Files to Create:**
- `database/collections/cycles_test.go`
- `database/collections/notifications_test.go`
- `database/collections/subscriptions_test.go`

**Tests to Implement:**

**cycles_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestGetCycle_Success` | Retrieve cycle by valid ID | Mock MongoDB |
| `TestGetCycle_InvalidObjectID` | Invalid ObjectID format | Mock MongoDB |
| `TestGetCycle_NotFound` | Cycle doesn't exist | Mock MongoDB |

**notifications_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestGetNotification_Success` | Retrieve notification by task name | Mock MongoDB |
| `TestGetNotification_NotFound` | Notification doesn't exist | Mock MongoDB |

**subscriptions_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestGetSubscription_Success` | Retrieve subscription by valid ID | Mock MongoDB |
| `TestGetSubscription_InvalidObjectID` | Invalid ObjectID format | Mock MongoDB |
| `TestGetSubscription_NotFound` | Subscription doesn't exist | Mock MongoDB |

**Estimated Coverage Target:** 85%+

#### 1.5 AWS Services Package (`services/aws/`)

**Files to Create:**
- `services/aws/ses_test.go`
- `services/aws/sts_test.go` (enhance existing)

**Tests to Implement:**

**ses_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestSESEmailClient_Initialization` | Initialize SES client | Mock AWS config |
| `TestNewSESEmail` | Create new email context | None |
| `TestBuildMessage_Success` | Build email with all fields | None |
| `TestBuildMessage_WithAttachment` | Build email with PDF attachment | File system |
| `TestBuildMessage_NoAttachment` | Build email without attachment | None |
| `TestSend_Success` | Send email successfully | Mock SES |
| `TestSend_Failure` | Handle SES send error | Mock SES |
| `TestSend_DeletesAttachment` | Verify attachment cleanup | File system |

**sts_test.go (enhancements):**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestAssumedRoleConfig` | Existing test (✓) | None |
| `TestAssumedRoleConfig_NoRegion` | Missing region configuration | Mock AWS |
| `TestAssumedRoleConfig_InvalidRole` | Invalid role ARN | Mock AWS |

**Estimated Coverage Target:** 80%+

#### 1.6 Mailgun Services Package (`services/mailgun/`)

**Files to Create:**
- `services/mailgun/mailgun_test.go`

**Tests to Implement:**

| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestMailgunEmail_BuildMessage` | Build email message | None |
| `TestMailgunEmail_Send` | Send email (stub returns nil) | None |

**Estimated Coverage Target:** 90%+

#### 1.7 Main Package

**Files to Create:**
- `main_test.go`
- `initialize_test.go`
- `version_test.go`

**Tests to Implement:**

**main_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestAuth_ValidKey` | Auth middleware with valid key | None |
| `TestAuth_InvalidKey` | Auth middleware with invalid key | None |
| `TestAuth_MissingKey` | Auth middleware with missing key | None |

**initialize_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestInit_Success` | Initialize DB and AWS clients | Mock DB, Mock AWS |
| `TestInit_DBFailure` | Handle DB initialization failure | Mock DB |
| `TestInit_AWSFailure` | Handle AWS initialization failure | Mock AWS |

**version_test.go:**
| Test Name | Description | Mocking Required |
|-----------|-------------|------------------|
| `TestVersion_FlagSet` | Version flag triggers exit | None |
| `TestVersion_FlagNotSet` | No version flag, continues | None |

**Estimated Coverage Target:** 70%+

### Priority 2: Integration Tests (MEDIUM)

Integration tests validate component interactions with real or containerized dependencies.

#### 2.1 Database Integration Tests

**Files to Create:**
- `database/mongo_integration_test.go`
- `database/collections/integration_test.go`

**Approach:**
- Use `testcontainers-go` to spin up real MongoDB container
- Test actual database operations
- Validate BSON serialization/deserialization
- Test error scenarios with real database

**Tests to Implement:**

| Test Name | Description | Dependencies |
|-----------|-------------|--------------|
| `TestIntegration_MongoConnection` | Connect to real MongoDB | Testcontainers |
| `TestIntegration_CycleOperations` | CRUD operations on cycles | Testcontainers |
| `TestIntegration_NotificationOperations` | CRUD operations on notifications | Testcontainers |
| `TestIntegration_SubscriptionOperations` | CRUD operations on subscriptions | Testcontainers |

**Estimated Coverage Target:** Validates database layer integrity

#### 2.2 HTTP Handler Integration Tests

**Files to Create:**
- `controllers/integration_test.go`

**Approach:**
- Test controllers with mocked external dependencies but real routing
- Use `httptest.Server` for full HTTP stack testing
- Validate request/response handling

**Tests to Implement:**

| Test Name | Description | Dependencies |
|-----------|-------------|--------------|
| `TestIntegration_TasksRouter_FullFlow` | Complete HTTP request flow | Mock DB, Mock AWS |
| `TestIntegration_EmailReport_EndToEnd` | Email report from request to response | Mock DB, Mock AWS, Mock API |

**Estimated Coverage Target:** Validates HTTP layer

### Priority 3: End-to-End (E2E) Tests (MEDIUM)

E2E tests validate complete application workflows.

#### 3.1 E2E Test Infrastructure

**Files to Create:**
- `e2e/e2e_test.go`
- `e2e/helpers.go`
- `e2e/fixtures.go`
- `e2e/README.md`

**Approach:**
- Start actual application server
- Use real HTTP client to make requests
- Use testcontainers for MongoDB
- Mock external services (AWS SES, Con-PCA API)
- Validate complete request-response cycles

**Infrastructure Components:**
1. **Test Server Setup**: Start HTTP server on random port
2. **MongoDB Container**: Spin up MongoDB with testcontainers
3. **Fixture Management**: Load test data into MongoDB
4. **Mock Servers**: HTTP servers for AWS SES and Con-PCA API
5. **Cleanup**: Proper teardown after tests

#### 3.2 E2E Test Scenarios

**Tests to Implement:**

| Test Name | Description | Validates |
|-----------|-------------|-----------|
| `TestE2E_HealthCheck` | GET / returns healthy | Server startup, routing |
| `TestE2E_EmailReport_CycleReport` | Complete cycle email report flow | Full email workflow |
| `TestE2E_EmailReport_Authentication` | Invalid API key rejected | Auth middleware |
| `TestE2E_EmailReport_InvalidCycleID` | Handle invalid cycle ID | Error handling |
| `TestE2E_PDFReport` | PDF report generation | PDF endpoint |
| `TestE2E_ConcurrentRequests` | Multiple simultaneous requests | Concurrency handling |

**Estimated Coverage Target:** Validates complete application workflows

### Priority 4: Test Infrastructure & Tooling (HIGH)

#### 4.1 Mocking Infrastructure

**Files to Create:**
- `mocks/mongo_mock.go` - MongoDB mock interfaces
- `mocks/aws_mock.go` - AWS SES/STS mock interfaces
- `mocks/http_mock.go` - HTTP client mock interfaces

**Dependencies to Add:**
```go
require (
    github.com/stretchr/testify v1.8.4
    github.com/testcontainers/testcontainers-go v0.26.0
    go.mongodb.org/mongo-driver v1.11.2
)
```

#### 4.2 Test Helpers

**Files to Create:**
- `testutils/fixtures.go` - Test data fixtures
- `testutils/helpers.go` - Common test utilities
- `testutils/assertions.go` - Custom assertions

**Utilities to Implement:**
- `CreateTestCycle()` - Generate test cycle data
- `CreateTestSubscription()` - Generate test subscription data
- `CreateTestNotification()` - Generate test notification data
- `SetupTestDB()` - Initialize test database
- `CleanupTestDB()` - Clean up test database
- `CreateMockHTTPServer()` - Create mock HTTP server

#### 4.3 CI/CD Integration

**Files to Modify:**
- `.github/workflows/build.yml`

**Changes Required:**

1. **Add Coverage Reporting:**
   ```yaml
   - name: Test application with coverage
     run: go test -v -coverprofile=coverage.out -covermode=atomic ./...
   
   - name: Generate coverage report
     run: go tool cover -html=coverage.out -o coverage.html
   
   - name: Upload coverage artifact
     uses: actions/upload-artifact@v3
     with:
       name: coverage-report
       path: coverage.html
   
   - name: Check coverage threshold
     run: |
       coverage=$(go tool cover -func=coverage.out | grep total | awk '{print $3}' | sed 's/%//')
       threshold=70
       if (( $(echo "$coverage < $threshold" | bc -l) )); then
         echo "Coverage $coverage% is below threshold $threshold%"
         exit 1
       fi
   ```

2. **Add E2E Test Job:**
   ```yaml
   e2e-test:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v3
       - uses: actions/setup-go@v3
         with:
           go-version: "1.20"
       - name: Install dependencies
         run: go mod download
       - name: Run E2E tests
         run: go test -v -tags=e2e ./e2e/...
   ```

3. **Add Test Matrix for Different Go Versions:**
   - Already exists (Go 1.19, 1.20) ✓
   - Ensure coverage runs on all versions

**Estimated Coverage Target:** 70% minimum, 85% target

## Test Development Guidelines

### 1. Test Structure

Follow the Arrange-Act-Assert (AAA) pattern:

```go
func TestExample(t *testing.T) {
    // Arrange: Set up test data and mocks
    expected := "expected value"
    
    // Act: Execute the function under test
    actual := FunctionUnderTest()
    
    // Assert: Verify the results
    assert.Equal(t, expected, actual)
}
```

### 2. Table-Driven Tests

Use table-driven tests for multiple scenarios:

```go
func TestExample(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        {"valid input", "test", "TEST"},
        {"empty input", "", ""},
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            actual := FunctionUnderTest(tt.input)
            assert.Equal(t, tt.expected, actual)
        })
    }
}
```

### 3. Mocking External Dependencies

Use interfaces and dependency injection:

```go
type EmailSender interface {
    Send() error
}

func ProcessEmail(sender EmailSender) error {
    return sender.Send()
}

// In tests
type MockEmailSender struct {
    mock.Mock
}

func (m *MockEmailSender) Send() error {
    args := m.Called()
    return args.Error(0)
}
```

### 4. Test Isolation

- Each test should be independent
- Use `t.Cleanup()` for resource cleanup
- Don't rely on test execution order
- Reset global state between tests

### 5. Naming Conventions

- Test files: `*_test.go`
- Test functions: `Test<FunctionName>_<Scenario>`
- Table test cases: Use descriptive names
- E2E tests: Use build tag `// +build e2e`

## Coverage Goals

### Phase 1: Foundation (Weeks 1-2)
- **Target**: 40% overall coverage
- **Focus**: Core unit tests for controllers, notifications, database

### Phase 2: Expansion (Weeks 3-4)
- **Target**: 70% overall coverage
- **Focus**: Complete unit tests, add integration tests

### Phase 3: Comprehensive (Weeks 5-6)
- **Target**: 85% overall coverage
- **Focus**: E2E tests, edge cases, error scenarios

### Final Target
- **Overall**: 85%+ coverage
- **Critical paths**: 95%+ coverage (email workflow, authentication)
- **Error handling**: 80%+ coverage

## Package-Specific Coverage Targets

| Package | Current | Target | Priority |
|---------|---------|--------|----------|
| `main` | 0.0% | 70% | HIGH |
| `controllers` | 12.5% | 90% | HIGH |
| `notifications` | 0.0% | 85% | HIGH |
| `database` | 0.0% | 80% | HIGH |
| `database/collections` | 0.0% | 85% | HIGH |
| `services/aws` | 19.4% | 80% | MEDIUM |
| `services/mailgun` | 0.0% | 90% | LOW |

## Testing Workflow

### Local Development

1. **Run all tests:**
   ```bash
   make test
   # or
   go test -v ./...
   ```

2. **Run tests with coverage:**
   ```bash
   go test -v -cover ./...
   ```

3. **Generate HTML coverage report:**
   ```bash
   go test -coverprofile=coverage.out ./...
   go tool cover -html=coverage.out -o coverage.html
   open coverage.html
   ```

4. **Run specific package tests:**
   ```bash
   go test -v ./controllers
   ```

5. **Run E2E tests:**
   ```bash
   go test -v -tags=e2e ./e2e/...
   ```

### CI/CD Workflow

1. **On Push/PR:**
   - Run lint (pre-commit hooks)
   - Run unit tests with coverage
   - Upload coverage artifacts
   - Fail if coverage below threshold (70%)

2. **On Merge to Develop:**
   - Run all tests including E2E
   - Generate coverage report
   - Create GitHub release (existing)

## Dependencies to Add

Add the following to `go.mod`:

```go
require (
    github.com/stretchr/testify v1.8.4
    github.com/testcontainers/testcontainers-go v0.26.0
    github.com/testcontainers/testcontainers-go/modules/mongodb v0.26.0
)
```

## Documentation Requirements

### 1. Test Documentation (TEST_DOCUMENTATION.md)

Document all implemented tests with:
- Test file locations
- Purpose of each test
- Coverage metrics
- How to run tests
- How to add new tests

### 2. E2E Test README (e2e/README.md)

Document E2E test infrastructure:
- Setup requirements
- How to run E2E tests
- How to add new E2E tests
- Mock server configurations

### 3. Update Main README.md

Add testing section:
- How to run tests
- Coverage requirements
- Pre-commit hooks

## Success Metrics

### Quantitative Metrics

1. **Code Coverage**: 85%+ overall
2. **Test Count**: 100+ unit tests, 20+ integration tests, 10+ E2E tests
3. **CI Pass Rate**: 95%+ on main branch
4. **Test Execution Time**: < 2 minutes for unit tests, < 5 minutes for all tests

### Qualitative Metrics

1. **Bug Detection**: Tests catch bugs before production
2. **Regression Prevention**: Tests prevent regressions
3. **Developer Confidence**: Developers feel confident making changes
4. **Documentation Quality**: Tests serve as documentation

## Risks and Mitigations

### Risk 1: External Service Dependencies

**Risk**: Tests depend on AWS SES, MongoDB, Con-PCA API
**Mitigation**: 
- Use mocks for unit tests
- Use testcontainers for integration tests
- Use mock HTTP servers for E2E tests
- Document setup for manual testing with real services

### Risk 2: Flaky Tests

**Risk**: Tests may be non-deterministic
**Mitigation**:
- Avoid time-based tests
- Use proper synchronization
- Isolate tests completely
- Run tests multiple times in CI

### Risk 3: Slow Test Execution

**Risk**: E2E tests may be slow
**Mitigation**:
- Run unit tests separately from E2E tests
- Use build tags to separate test types
- Parallelize test execution where possible
- Cache dependencies in CI

### Risk 4: Maintenance Burden

**Risk**: Tests may become outdated
**Mitigation**:
- Treat tests as first-class code
- Include test updates in code reviews
- Fail CI if tests are broken
- Document test patterns

## Implementation Timeline

### Week 1-2: Foundation
- Set up test infrastructure (mocks, helpers, fixtures)
- Implement Priority 1 unit tests (controllers, notifications)
- Update CI with coverage reporting
- Target: 40% coverage

### Week 3-4: Expansion
- Complete all unit tests (database, AWS services, main package)
- Implement integration tests
- Target: 70% coverage

### Week 5-6: Comprehensive Coverage
- Implement E2E test infrastructure
- Create E2E test scenarios
- Add edge case tests
- Final documentation
- Target: 85% coverage

## Appendix

### A. Test File Organization

```
con-pca-tasks/
├── controllers/
│   ├── controllers.go
│   ├── controllers_test.go (enhanced)
│   └── integration_test.go (new)
├── database/
│   ├── collections/
│   │   ├── cycles.go
│   │   ├── cycles_test.go (new)
│   │   ├── notifications.go
│   │   ├── notifications_test.go (new)
│   │   ├── subscriptions.go
│   │   ├── subscriptions_test.go (new)
│   │   └── integration_test.go (new)
│   ├── mongo.go
│   ├── mongo_test.go (new)
│   └── mongo_integration_test.go (new)
├── e2e/
│   ├── e2e_test.go (new)
│   ├── helpers.go (new)
│   ├── fixtures.go (new)
│   └── README.md (new)
├── mocks/
│   ├── mongo_mock.go (new)
│   ├── aws_mock.go (new)
│   └── http_mock.go (new)
├── notifications/
│   ├── manager.go
│   ├── manager_test.go (new)
│   ├── template.go
│   └── template_test.go (new)
├── services/
│   ├── aws/
│   │   ├── ses.go
│   │   ├── ses_test.go (new)
│   │   ├── sts.go
│   │   └── sts_test.go (enhanced)
│   └── mailgun/
│       ├── mailgun.go
│       └── mailgun_test.go (new)
├── testutils/
│   ├── fixtures.go (new)
│   ├── helpers.go (new)
│   └── assertions.go (new)
├── main_test.go (new)
├── initialize_test.go (new)
├── version_test.go (new)
├── TESTING_PLAN.md (this document)
└── TEST_DOCUMENTATION.md (new)
```

### B. Reference Links

- Go Testing: https://golang.org/pkg/testing/
- Testify: https://github.com/stretchr/testify
- Testcontainers: https://golang.testcontainers.org/
- Go Coverage: https://go.dev/blog/cover

### C. Contact and Support

For questions about this testing plan:
- Review the TEST_DOCUMENTATION.md for implementation details
- Check e2e/README.md for E2E test setup
- Refer to existing tests as examples
- Consult Go testing best practices

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-06  
**Author**: Devin (AI Software Engineer)  
**Status**: Draft - Pending Implementation
