package middleware

import (
	"context"
	"net/http"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
)

type contextKey string

const uidKey contextKey = "uid"

var firebaseAuthClient *auth.Client

func InitFirebaseAuth(ctx context.Context) error {
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: "truck-router1"})
	if err != nil {
		return err
	}
	firebaseAuthClient, err = app.Auth(ctx)
	return err
}

// AuthClient expõe o cliente do Auth pra quem precisa de metadado do usuário
// (idade da conta, provedores) — o S.O.S. usa pra gate de perfil novo.
func AuthClient() *auth.Client { return firebaseAuthClient }

func UIDFromContext(ctx context.Context) string {
	uid, _ := ctx.Value(uidKey).(string)
	return uid
}

func FirebaseAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		raw := strings.TrimPrefix(header, "Bearer ")
		token, err := firebaseAuthClient.VerifyIDToken(r.Context(), raw)
		if err != nil {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		ctx := context.WithValue(r.Context(), uidKey, token.UID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
