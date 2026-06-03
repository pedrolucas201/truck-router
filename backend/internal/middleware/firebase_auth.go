package middleware

import (
	"context"
	"net/http"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
)

var firebaseAuthClient *auth.Client

func InitFirebaseAuth(ctx context.Context) error {
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: "truck-router1"})
	if err != nil {
		return err
	}
	firebaseAuthClient, err = app.Auth(ctx)
	return err
}

func FirebaseAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		token := strings.TrimPrefix(header, "Bearer ")
		if _, err := firebaseAuthClient.VerifyIDToken(r.Context(), token); err != nil {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}
