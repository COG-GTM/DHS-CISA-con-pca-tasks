package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestAuth_ValidKey(t *testing.T) {
	os.Setenv("API_ACCESS_KEY", "test-api-key")
	defer os.Unsetenv("API_ACCESS_KEY")

	apiKey = os.Getenv("API_ACCESS_KEY")

	handler := Auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("success"))
	}))

	req := httptest.NewRequest(http.MethodGet, "/tasks", nil)
	req.Header.Set("api_key", "test-api-key")
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	res := w.Result()
	defer res.Body.Close()

	assert.Equal(t, http.StatusOK, res.StatusCode)
}

func TestAuth_InvalidKey(t *testing.T) {
	os.Setenv("API_ACCESS_KEY", "test-api-key")
	defer os.Unsetenv("API_ACCESS_KEY")

	apiKey = os.Getenv("API_ACCESS_KEY")

	handler := Auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("success"))
	}))

	req := httptest.NewRequest(http.MethodGet, "/tasks", nil)
	req.Header.Set("api_key", "wrong-key")
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	res := w.Result()
	defer res.Body.Close()

	assert.Equal(t, http.StatusForbidden, res.StatusCode)
}

func TestAuth_MissingKey(t *testing.T) {
	os.Setenv("API_ACCESS_KEY", "test-api-key")
	defer os.Unsetenv("API_ACCESS_KEY")

	apiKey = os.Getenv("API_ACCESS_KEY")

	handler := Auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("success"))
	}))

	req := httptest.NewRequest(http.MethodGet, "/tasks", nil)
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	res := w.Result()
	defer res.Body.Close()

	assert.Equal(t, http.StatusForbidden, res.StatusCode)
}

func TestAuth_EmptyKey(t *testing.T) {
	os.Setenv("API_ACCESS_KEY", "test-api-key")
	defer os.Unsetenv("API_ACCESS_KEY")

	apiKey = os.Getenv("API_ACCESS_KEY")

	handler := Auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("success"))
	}))

	req := httptest.NewRequest(http.MethodGet, "/tasks", nil)
	req.Header.Set("api_key", "")
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	res := w.Result()
	defer res.Body.Close()

	assert.Equal(t, http.StatusForbidden, res.StatusCode)
}
