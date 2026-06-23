package handlers

import (
	"io"
	"log"
	"net/http"
	"net/url"
	"time"
)

var httpClient = &http.Client{Timeout: 10 * time.Second}

// forward faz GET em targetURL, copia status + body para w.
// rawQuery é repassado sem re-encoding (preserva vehicle[height] literais).
func forward(w http.ResponseWriter, targetURL string, rawQuery string) {
	req, err := http.NewRequest(http.MethodGet, targetURL+"?"+rawQuery, nil)
	if err != nil {
		log.Printf("forward build request: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	resp, err := httpClient.Do(req)
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

// forwardAndCache faz GET em targetURL e, se a resposta for 200,
// armazena body + content-type no cache de rotas com a chave fornecida.
func forwardAndCache(w http.ResponseWriter, targetURL, rawQuery, key string) {
	req, err := http.NewRequest(http.MethodGet, targetURL+"?"+rawQuery, nil)
	if err != nil {
		log.Printf("forwardAndCache build request: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		log.Printf("forwardAndCache do request %s: %v", targetURL, err)
		http.Error(w, "internal error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("forwardAndCache read body: %v", err)
		http.Error(w, "internal error", http.StatusBadGateway)
		return
	}

	ct := resp.Header.Get("Content-Type")
	if resp.StatusCode == http.StatusOK {
		routeCacheSet(key, body, ct)
	}

	w.Header().Set("Content-Type", ct)
	w.WriteHeader(resp.StatusCode)
	w.Write(body)
}

// appendKey adiciona apikey=value ao raw query string existente.
func appendKey(rawQuery, param, value string) string {
	if rawQuery == "" {
		return url.QueryEscape(param) + "=" + url.QueryEscape(value)
	}
	return rawQuery + "&" + url.QueryEscape(param) + "=" + url.QueryEscape(value)
}
