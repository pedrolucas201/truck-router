package middleware

import (
	"net/http"
	"os"
)

func ApiKey(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		expected := os.Getenv("BACKEND_API_KEY")
		if expected == "" || r.Header.Get("X-Api-Key") != expected {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}
