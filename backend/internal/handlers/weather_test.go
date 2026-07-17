package handlers

import "testing"

// classifyForecast é o coração da feature (decide o que vira alerta pro
// caminhão). Trava os limiares e a ORDEM de prioridade (vento antes de chuva).
func TestClassifyForecast(t *testing.T) {
	cases := []struct {
		name     string
		f        hereWxForecast
		wantKind string
	}{
		{"calmo vira nada", hereWxForecast{WindSpeed: 20, RainFall: 0, Visibility: 15}, ""},
		{"vento no limite", hereWxForecast{WindSpeed: 45}, "wind"},
		{"vento abaixo nao alerta", hereWxForecast{WindSpeed: 44.9}, ""},
		// rainFall em CM: 0.6cm=6mm forte; 0.4cm=4mm nao alerta.
		{"chuva forte + prob alta", hereWxForecast{RainFall: 0.6, PrecipitationProbability: 80}, "rain"},
		{"chuva abaixo do limite nao alerta", hereWxForecast{RainFall: 0.4, PrecipitationProbability: 90}, ""},
		{"chuva forte mas prob baixa nao alerta", hereWxForecast{RainFall: 0.6, PrecipitationProbability: 40}, ""},
		{"neblina", hereWxForecast{Visibility: 1.5}, "fog"},
		{"visibilidade zero (dado ausente) nao alerta", hereWxForecast{Visibility: 0}, ""},
		{"vento ganha de chuva", hereWxForecast{WindSpeed: 50, RainFall: 0.6, PrecipitationProbability: 90}, "wind"},
	}
	for _, c := range cases {
		if kind, _, hit := classifyForecast(c.f); kind != c.wantKind || hit != (c.wantKind != "") {
			t.Errorf("%s: got kind=%q hit=%v, want kind=%q", c.name, kind, hit, c.wantKind)
		}
	}
}
