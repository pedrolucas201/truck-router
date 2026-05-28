package handlers

import (
	"io"
	"log"
	"net/http"
	"net/url"
)

// forward faz GET em targetURL, copia status + body para w.
// rawQuery é repassado sem re-encoding (preserva vehicle[height] literais).
func forward(w http.ResponseWriter, targetURL string, rawQuery string) {
	req, err := http.NewRequest(http.MethodGet, targetURL+"?"+rawQuery, nil)
	if err != nil {
		log.Printf("forward build request: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("forward do request %s: %v", targetURL, err)
		http.Error(w, "internal error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

// appendKey adiciona apikey=value ao raw query string existente.
func appendKey(rawQuery, param, value string) string {
	if rawQuery == "" {
		return url.QueryEscape(param) + "=" + url.QueryEscape(value)
	}
	return rawQuery + "&" + url.QueryEscape(param) + "=" + url.QueryEscape(value)
}
