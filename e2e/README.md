# End-to-End (E2E) Testing

This directory contains end-to-end tests for the con-pca-tasks application.

## Overview

E2E tests validate complete application workflows from HTTP request to response, using real or mocked external dependencies. These tests ensure that all components work together correctly.

## Prerequisites

To run E2E tests locally, you need:

- **Go 1.20+**
- **Docker** (for testcontainers)
- **MongoDB** (via testcontainers or local instance)
- **AWS credentials** (for real tests) or mock servers (for development)

## Test Structure

### E2E Test Files

- `e2e_test.go` - Main E2E test suite
- `helpers.go` - Helper functions for test setup/teardown
- `fixtures.go` - Test data fixtures

### Test Scenarios

Current E2E tests cover:

1. **Health Check** - Validates server startup and basic routing
2. **Authentication** - Tests API key authentication middleware
3. **PDF Report Generation** - Tests PDF report endpoint

Future tests should cover:

- Complete email report workflow (requires MongoDB setup)
- Error handling scenarios
- Concurrent request handling

## Running E2E Tests

### Run All E2E Tests

```bash
cd /home/ubuntu/repos/DHS-CISA-con-pca-tasks
go test -v -tags=e2e ./e2e/...
```

### Run Specific E2E Test

```bash
go test -v -tags=e2e ./e2e -run TestE2E_HealthCheck
```

### Run with Verbose Output

```bash
go test -v -tags=e2e ./e2e/... -test.v
```

## Test Build Tags

E2E tests use the `e2e` build tag to separate them from unit tests. This allows:

- Running unit tests quickly without E2E overhead
- Running E2E tests separately in CI/CD
- Conditional compilation based on test type

To include E2E tests in your test run, use the `-tags=e2e` flag.

## Test Setup

### Automatic Setup

The E2E tests automatically:

1. Start HTTP server on a random port
2. Set up environment variables
3. Initialize test fixtures
4. Clean up resources after tests

### Manual Setup (for debugging)

If you need to run the server manually for debugging:

```bash
# Set environment variables
export API_ACCESS_KEY=test-api-key
export API_URL=http://localhost:5000
export MONGO_URI=mongodb://localhost:27017

# Run the application
go run *.go
```

Then run E2E tests against the running server by modifying the test configuration.

## Writing E2E Tests

### Example E2E Test

```go
// +build e2e

func TestE2E_MyFeature(t *testing.T) {
    // Arrange: Set up test server and fixtures
    srv, cleanup := setupTestServer(t)
    defer cleanup()
    
    // Act: Make HTTP request
    resp, err := http.Get(srv.URL + "/tasks/test-id/reports/cycle/pdf")
    require.NoError(t, err)
    defer resp.Body.Close()
    
    // Assert: Validate response
    assert.Equal(t, http.StatusOK, resp.StatusCode)
}
```

### Best Practices

1. **Isolation**: Each test should be independent
2. **Cleanup**: Always clean up resources (use defer)
3. **Assertions**: Use testify/assert for clear assertions
4. **Error Handling**: Check all errors
5. **Timeouts**: Use context with timeouts for HTTP requests

## Troubleshooting

### Port Already in Use

If you get "address already in use" errors, the test server port may be occupied. The E2E tests use a random port to avoid conflicts.

### Docker Not Running

E2E tests that use testcontainers require Docker:

```bash
# Check Docker status
docker info

# Start Docker (Linux)
sudo systemctl start docker
```

### MongoDB Connection Issues

If MongoDB connection fails:

1. Check MongoDB is running: `docker ps | grep mongo`
2. Verify connection string in environment variables
3. Check network connectivity

### Test Timeouts

If tests timeout:

1. Increase timeout in test configuration
2. Check system resources (CPU, memory)
3. Verify external services are responsive

## CI/CD Integration

E2E tests run in CI/CD pipeline:

```yaml
e2e-test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v3
    - uses: actions/setup-go@v3
      with:
        go-version: "1.20"
    - name: Run E2E tests
      run: go test -v -tags=e2e ./e2e/...
```

## Future Enhancements

Planned improvements:

1. **MongoDB Testcontainers**: Use real MongoDB for integration tests
2. **Mock External APIs**: Create mock servers for Con-PCA API
3. **Performance Tests**: Add load testing scenarios
4. **Visual Regression**: Test PDF generation output
5. **Error Scenarios**: Test failure modes and error handling

## Support

For questions or issues with E2E tests:

- Check the main TESTING_PLAN.md for overall testing strategy
- Review TEST_DOCUMENTATION.md for detailed test documentation
- Consult Go testing best practices: https://golang.org/pkg/testing/
