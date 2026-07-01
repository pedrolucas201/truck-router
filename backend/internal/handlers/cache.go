package handlers

import (
	"crypto/sha256"
	"fmt"
	"net/url"
	"sync"
	"time"
)

// 3min: a rota agora carrega trânsito (dynamicSpeedInfo). Cache longo serviria
// congestionamento velho. 3min ainda dedupa rajada (reroute/retry) mas mantém
// o trânsito fresco o suficiente pra navegação.
const routeCacheTTL = 3 * time.Minute

type cacheEntry struct {
	body        []byte
	contentType string
	expiresAt   time.Time
}

var routeCache sync.Map

// routeCacheKey deriva uma chave determinística da query string,
// removendo o apikey para que requisições idênticas de clientes diferentes coincidam.
func routeCacheKey(rawQuery string) string {
	v, err := url.ParseQuery(rawQuery)
	if err != nil {
		h := sha256.Sum256([]byte(rawQuery))
		return fmt.Sprintf("%x", h)
	}
	v.Del("apikey")
	h := sha256.Sum256([]byte(v.Encode()))
	return fmt.Sprintf("%x", h)
}

func routeCacheGet(key string) (cacheEntry, bool) {
	val, ok := routeCache.Load(key)
	if !ok {
		return cacheEntry{}, false
	}
	entry := val.(cacheEntry)
	if time.Now().After(entry.expiresAt) {
		routeCache.Delete(key)
		return cacheEntry{}, false
	}
	return entry, true
}

func routeCacheSet(key string, body []byte, contentType string) {
	routeCache.Store(key, cacheEntry{
		body:        body,
		contentType: contentType,
		expiresAt:   time.Now().Add(routeCacheTTL),
	})
}
