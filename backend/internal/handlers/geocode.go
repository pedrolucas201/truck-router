package handlers

import (
	"net/http"
	"os"
)

// Proxy endpoints HERE geocoding — preserva todos os query params do Flutter,
// injeta apikey server-side.

func HereAutocomplete(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	forward(w, "https://autocomplete.search.hereapi.com/v1/autocomplete", q)
}

func HereGeocode(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	forward(w, "https://geocode.search.hereapi.com/v1/geocode", q)
}

func HereDiscover(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	forward(w, "https://discover.search.hereapi.com/v1/discover", q)
}

func HereLookup(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	forward(w, "https://lookup.search.hereapi.com/v1/lookup", q)
}

func HereRevgeocode(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "apikey", os.Getenv("HERE_API_KEY"))
	forward(w, "https://revgeocode.search.hereapi.com/v1/revgeocode", q)
}

func TomTomGeocode(w http.ResponseWriter, r *http.Request) {
	q := appendKey(r.URL.RawQuery, "key", os.Getenv("TOMTOM_API_KEY"))
	forward(w, "https://api.tomtom.com/search/2/structuredGeocode.json", q)
}
