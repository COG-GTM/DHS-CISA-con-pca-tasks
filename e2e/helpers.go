
package e2e

import (
	"net/http/httptest"
	"os"
	"testing"

	"github.com/cisagov/con-pca-tasks/controllers"
	"github.com/go-chi/chi/v5"
)

func setupTestServer(t *testing.T) (*httptest.Server, func()) {
	t.Helper()

	os.Setenv("API_ACCESS_KEY", "test-api-key-e2e")
	os.Setenv("API_URL", "http://localhost:5000")
	os.Setenv("MONGO_URI", "mongodb://localhost:27017")

	r := chi.NewRouter()
	r.Mount("/tasks", controllers.TasksRouter())

	server := httptest.NewServer(r)

	cleanup := func() {
		server.Close()
		os.Unsetenv("API_ACCESS_KEY")
		os.Unsetenv("API_URL")
		os.Unsetenv("MONGO_URI")
	}

	return server, cleanup
}

func setupAuthenticatedTestServer(t *testing.T, apiKey string) (*httptest.Server, func()) {
	t.Helper()

	os.Setenv("API_ACCESS_KEY", apiKey)
	os.Setenv("API_URL", "http://localhost:5000")
	os.Setenv("MONGO_URI", "mongodb://localhost:27017")

	r := chi.NewRouter()
	
	r.Mount("/tasks", controllers.TasksRouter())

	server := httptest.NewServer(r)

	cleanup := func() {
		server.Close()
		os.Unsetenv("API_ACCESS_KEY")
		os.Unsetenv("API_URL")
		os.Unsetenv("MONGO_URI")
	}

	return server, cleanup
}
