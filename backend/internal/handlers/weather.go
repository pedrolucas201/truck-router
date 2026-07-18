package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"sync"
	"time"
)

// /weather/route DIGERE o clima da rota: recebe os pontos amostrados da polyline
// com a hora projetada de passagem, faz fan-out pro HERE Destination Weather
// server-side e devolve SÓ as células severas (JSON pequeno). O app não faz o
// loop porque o HERE devolve ~86KB por ponto — 20 pontos = 1,7MB no 4G do
// caminhoneiro. Aqui o telefone manda a rota e recebe alertas prontos.

// Limiares de severidade — KNOBS DE CAMPO, ponto de partida grounded, NÃO
// validados em estrada. Calibrar com o Gilberto: pro caminhão alto o vento é o
// que tomba, então o gatilho de vento é baixo (o HERE dá windSpeed sustentado,
// não rajada — a rajada real é maior). visibility do HERE vem em KM.
// ponytail: constantes; se um dia virar por-perfil-de-caminhão, sobe pra config.
const (
	wxWindKmh  = 45.0 // vento sustentado (km/h)
	// HERE default é MÉTRICO e o rainFall métrico vem em CM (medido 2026-07-17:
	// units=metric 0.24 vs imperial 0.09 = razão polegada→cm). 0.5cm ≈ 5mm/h =
	// chuva forte. NÃO usar mm aqui — 4 seria 40mm/h e nunca dispararia.
	wxRainCm    = 0.5 // chuva forte (cm/h)
	wxRainProb  = 60  // só com probabilidade razoável — não gritar em previsão fraca
	wxVisKm     = 2.0 // neblina de serra (km)
	wxFanoutMax = 8   // chamadas HERE simultâneas
	wxMaxPoints = 64  // teto defensivo de pontos por request
	wxMatchSlop = 90 * time.Minute
	// Ponto que o caminhão alcança em <= isto usa OBSERVATION (condição real
	// agora), não forecast — a previsão do HERE erra chuva convectiva local
	// (medido: chuva real → forecast 0.03cm, observation 0.48cm).
	wxNowcastHorizon = 45 * time.Minute
)

type wxPoint struct {
	Lat  float64 `json:"lat"`
	Lng  float64 `json:"lng"`
	Time string  `json:"time"` // ISO8601 da hora projetada de passagem
}

type wxAlert struct {
	Lat   float64 `json:"lat"`
	Lng   float64 `json:"lng"`
	Time  string  `json:"time"`
	Kind  string  `json:"kind"`  // "rain" | "wind" | "fog"
	Label string  `json:"label"` // pronto pro usuário
	Icon  string  `json:"icon"`  // iconName do HERE
}

// Só os campos do forecast HERE que eu classifico.
type hereWxForecast struct {
	Time                     string  `json:"time"`
	RainFall                 float64 `json:"rainFall"`
	PrecipitationProbability int     `json:"precipitationProbability"`
	WindSpeed                float64 `json:"windSpeed"`
	Visibility               float64 `json:"visibility"`
	IconName                 string  `json:"iconName"`
}

type hereWxResp struct {
	Places []struct {
		HourlyForecasts []struct {
			Forecasts []hereWxForecast `json:"forecasts"`
		} `json:"hourlyForecasts"`
	} `json:"places"`
}

// observation (condição atual) tem o MESMO conjunto de campos, só aninha em
// places[].observations[] em vez de hourlyForecasts[].forecasts[].
type hereObsResp struct {
	Places []struct {
		Observations []hereWxForecast `json:"observations"`
	} `json:"places"`
}

// classifyForecast: dado um forecast HERE, diz se é severo pro caminhão e qual
// alerta emitir. Ordem = mais perigoso primeiro. Função PURA (testável sem rede).
func classifyForecast(f hereWxForecast) (kind, label string, hit bool) {
	switch {
	case f.WindSpeed >= wxWindKmh:
		return "wind", "Vento forte", true
	case f.RainFall >= wxRainCm && f.PrecipitationProbability >= wxRainProb:
		return "rain", "Chuva forte", true
	case f.Visibility > 0 && f.Visibility <= wxVisKm:
		return "fog", "Visibilidade baixa", true
	}
	return "", "", false
}

func WeatherRoute(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Points []wxPoint `json:"points"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if len(body.Points) > wxMaxPoints {
		body.Points = body.Points[:wxMaxPoints]
	}

	key := os.Getenv("HERE_API_KEY")
	sem := make(chan struct{}, wxFanoutMax)
	var wg sync.WaitGroup
	var mu sync.Mutex
	alerts := []wxAlert{}

	for _, p := range body.Points {
		wg.Add(1)
		go func(p wxPoint) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if a, ok := forecastAt(p, key); ok {
				mu.Lock()
				alerts = append(alerts, a)
				mu.Unlock()
			}
		}(p)
	}
	wg.Wait()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"alerts": alerts})
}

// forecastAt escolhe a fonte pelo tempo de chegada ao ponto: perto no tempo
// (<= wxNowcastHorizon) usa OBSERVATION (condição real agora — a previsão erra
// chuva convectiva local); longe usa o forecast na hora projetada. Falha = sem
// alerta, silencioso; clima é opcional, nunca derruba nada.
func forecastAt(p wxPoint, key string) (wxAlert, bool) {
	target, err := time.Parse(time.RFC3339, p.Time)
	if err != nil {
		return wxAlert{}, false
	}
	if time.Until(target) <= wxNowcastHorizon {
		if a, ok := observeAt(p, key); ok {
			return a, true
		}
		// observation falhou → cai pro forecast (melhor algo que nada).
	}
	return forecastHourlyAt(p, target, key)
}

// observeAt classifica a condição ATUAL do ponto (products=observation).
func observeAt(p wxPoint, key string) (wxAlert, bool) {
	data, ok := fetchJSON(fmt.Sprintf(
		"https://weather.hereapi.com/v3/report?products=observation&location=%f,%f&apiKey=%s",
		p.Lat, p.Lng, url.QueryEscape(key)))
	if !ok {
		return wxAlert{}, false
	}
	var hw hereObsResp
	if err := json.Unmarshal(data, &hw); err != nil ||
		len(hw.Places) == 0 || len(hw.Places[0].Observations) == 0 {
		return wxAlert{}, false
	}
	obs := hw.Places[0].Observations[0]
	kind, label, hit := classifyForecast(obs)
	if !hit {
		return wxAlert{}, false
	}
	return wxAlert{Lat: p.Lat, Lng: p.Lng, Time: p.Time, Kind: kind, Label: label, Icon: obs.IconName}, true
}

// forecastHourlyAt classifica o forecast horário mais próximo da hora projetada.
func forecastHourlyAt(p wxPoint, target time.Time, key string) (wxAlert, bool) {
	data, ok := fetchJSON(fmt.Sprintf(
		"https://weather.hereapi.com/v3/report?products=forecastHourly&location=%f,%f&apiKey=%s",
		p.Lat, p.Lng, url.QueryEscape(key)))
	if !ok {
		return wxAlert{}, false
	}
	var hw hereWxResp
	if err := json.Unmarshal(data, &hw); err != nil ||
		len(hw.Places) == 0 || len(hw.Places[0].HourlyForecasts) == 0 {
		return wxAlert{}, false
	}
	best, ok := nearestForecast(hw.Places[0].HourlyForecasts[0].Forecasts, target)
	if !ok {
		return wxAlert{}, false
	}
	kind, label, hit := classifyForecast(best)
	if !hit {
		return wxAlert{}, false
	}
	return wxAlert{Lat: p.Lat, Lng: p.Lng, Time: best.Time, Kind: kind, Label: label, Icon: best.IconName}, true
}

// fetchJSON faz GET e devolve o corpo se 200. Qualquer erro = (nil, false).
func fetchJSON(u string) ([]byte, bool) {
	resp, err := httpClient.Get(u)
	if err != nil {
		return nil, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, false
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, false
	}
	return data, true
}

// nearestForecast acha o forecast horário mais próximo do horário alvo; recusa se
// o mais próximo ainda estiver a mais de wxMatchSlop (fora do horizonte da API).
func nearestForecast(fcs []hereWxForecast, target time.Time) (hereWxForecast, bool) {
	var best hereWxForecast
	found := false
	bestDiff := time.Duration(1<<63 - 1)
	for _, f := range fcs {
		ft, err := time.Parse(time.RFC3339, f.Time)
		if err != nil {
			continue
		}
		d := ft.Sub(target)
		if d < 0 {
			d = -d
		}
		if d < bestDiff {
			bestDiff, best, found = d, f, true
		}
	}
	if !found || bestDiff > wxMatchSlop {
		return hereWxForecast{}, false
	}
	return best, true
}
