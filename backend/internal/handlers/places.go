package handlers

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
)

// Google Places (New) — busca por NOME de lugar (empresa, posto, CD, portaria).
// Medido em 2026-09-09 com 20 nomes que um motorista digita: a HERE (discover)
// achou 14, a Google 20 — inclusive "Ceasa SJC" (que na HERE só existe como
// CEAGESP), o CD do Mercado Livre em Cajamar e a portaria da Johnson.
//
// Custo: Autocomplete + Details Essentials, 10k grátis/mês cada. A field mask
// do Details fica FIXA aqui (location + formattedAddress = Essentials):
// displayName viraria Pro (US$ 17/1k) e o app não tem como pedir por aqui.
// O nome já vem no texto do Autocomplete, de graça.

const placesBase = "https://places.googleapis.com/v1"
const placesDetailsMask = "location,formattedAddress"

// autocompleteBody monta o POST do Autocomplete (New) a partir dos params do
// app. `at` = lat,lng do motorista: vira locationBias (50 km, o máximo do
// círculo) E origin — origin faz a Google devolver distanceMeters em cada
// sugestão, que o ranking do app já usa. Sem at, só o país.
func autocompleteBody(input, at, session string) ([]byte, error) {
	b := map[string]any{
		"input":               input,
		"languageCode":        "pt-BR",
		"includedRegionCodes": []string{"br"},
	}
	if session != "" {
		b["sessionToken"] = session
	}
	if lat, lng, ok := parseAt(at); ok {
		b["origin"] = map[string]float64{"latitude": lat, "longitude": lng}
		b["locationBias"] = map[string]any{"circle": map[string]any{
			"center": map[string]float64{"latitude": lat, "longitude": lng},
			"radius": 50000.0,
		}}
	}
	return json.Marshal(b)
}

func parseAt(at string) (float64, float64, bool) {
	parts := strings.Split(at, ",")
	if len(parts) != 2 {
		return 0, 0, false
	}
	lat, e1 := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
	lng, e2 := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
	if e1 != nil || e2 != nil {
		return 0, 0, false
	}
	return lat, lng, true
}

// GooglePlacesAutocomplete — GET /google/places/autocomplete?input=&at=&session=
func GooglePlacesAutocomplete(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	input := strings.TrimSpace(q.Get("input"))
	if input == "" {
		http.Error(w, "input required", http.StatusBadRequest)
		return
	}
	body, err := autocompleteBody(input, q.Get("at"), q.Get("session"))
	if err != nil {
		log.Printf("places autocomplete body: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	forwardGoogle(w, http.MethodPost, placesBase+"/places:autocomplete", body, "")
}

// GooglePlacesDetails — GET /google/places/details?id=&session=
func GooglePlacesDetails(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	id := q.Get("id")
	if id == "" || strings.ContainsAny(id, "/?#") {
		http.Error(w, "id required", http.StatusBadRequest)
		return
	}
	target := placesBase + "/places/" + url.PathEscape(id) + "?languageCode=pt-BR"
	if s := q.Get("session"); s != "" {
		target += "&sessionToken=" + url.QueryEscape(s)
	}
	forwardGoogle(w, http.MethodGet, target, nil, placesDetailsMask)
}

// forwardGoogle: nas APIs novas da Google a chave e a field mask vão em header,
// não na query como no forward(). Mesma chave de servidor da Geocoding
// (restrita a geocoding-backend + places).
func forwardGoogle(w http.ResponseWriter, method, target string, body []byte, mask string) {
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, target, rd)
	if err != nil {
		log.Printf("forwardGoogle build request: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	req.Header.Set("X-Goog-Api-Key", os.Getenv("GOOGLE_GEOCODING_KEY"))
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if mask != "" {
		req.Header.Set("X-Goog-FieldMask", mask)
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		log.Printf("forwardGoogle do request %s: %v", target, err)
		http.Error(w, "internal error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}
