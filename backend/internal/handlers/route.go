package handlers

import (
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
)

// HereRoute: GET /route/here — proxy para router.hereapi.com/v8/routes
// Preserva raw query (vehicle[height] usa colchetes literais que não podem ser re-encoded).
func HereRoute(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	forward(w, "https://router.hereapi.com/v8/routes", q)
}

// TomTomRoute: GET /route/tomtom/{locs} — proxy para api.tomtom.com/routing/1/calculateRoute/{locs}/json
func TomTomRoute(w http.ResponseWriter, r *http.Request) {
	locs := chi.URLParam(r, "*")
	q := appendKey(r.URL.RawQuery, "key", os.Getenv("TOMTOM_API_KEY"))
	forward(w, "https://api.tomtom.com/routing/1/calculateRoute/"+locs+"/json", q)
}
