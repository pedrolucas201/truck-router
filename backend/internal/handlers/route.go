package handlers

import (
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
)

// HereRoute: GET /route/here — proxy para router.hereapi.com/v8/routes com cache em memória.
// Preserva raw query (vehicle[height] usa colchetes literais que não podem ser re-encoded).
// Cache TTL: 2h; chave derivada da query sem apikey.
func HereRoute(w http.ResponseWriter, r *http.Request) {
	key := routeCacheKey(r.URL.RawQuery)
	if entry, ok := routeCacheGet(key); ok {
		w.Header().Set("Content-Type", entry.contentType)
		w.WriteHeader(http.StatusOK)
		w.Write(entry.body)
		return
	}
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	forwardAndCache(w, "https://router.hereapi.com/v8/routes", q, key)
}

// TomTomRoute: GET /route/tomtom/{locs} — proxy para api.tomtom.com/routing/1/calculateRoute/{locs}/json
func TomTomRoute(w http.ResponseWriter, r *http.Request) {
	locs := chi.URLParam(r, "*")
	q := appendKey(r.URL.RawQuery, "key", os.Getenv("TOMTOM_API_KEY"))
	forward(w, "https://api.tomtom.com/routing/1/calculateRoute/"+locs+"/json", q)
}
