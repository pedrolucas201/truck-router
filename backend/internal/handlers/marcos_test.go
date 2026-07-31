package handlers

import (
	"math"
	"testing"
)

// P0 de campo 01/07 (Extrema-MG): "Fernão Dias km 936" caía longe do destino.
// Estes testes rodam contra o CSV real embutido — é ele que vai a produção.

func TestParseBr(t *testing.T) {
	casos := map[string]string{
		"BR-381 km 936":              "381",
		"br 116, km 280":             "116",
		"BR-40 km 650":               "040",
		"Rodovia Fernão Dias km 936": "381",
		"fernao dias km 936":         "381",
		"Via Dutra km 200":           "116",
		// estadual não vira BR: mapear seria inventar rodovia
		"Rodovia Anhanguera km 100":      "",
		"Rodovia dos Bandeirantes km 72": "",
		"Avenida Paulista 1000":          "",
	}
	for in, want := range casos {
		if got := ParseBr(in); got != want {
			t.Errorf("ParseBr(%q) = %q, quer %q", in, got, want)
		}
	}
}

func TestParseKm(t *testing.T) {
	casos := []struct {
		in    string
		km, m int
		ok    bool
	}{
		{"BR-381 km 936", 936, 0, true},
		{"BR-381 KM936", 936, 0, true},
		{"Fernão Dias KM 936+700", 936, 700, true},
		{"BR-116 km 280 + 500", 280, 500, true},
		{"Rodovia Fernão Dias", 0, 0, false},
	}
	for _, c := range casos {
		km, m, ok := ParseKm(c.in)
		if ok != c.ok || km != c.km || m != c.m {
			t.Errorf("ParseKm(%q) = (%d,%d,%v), quer (%d,%d,%v)", c.in, km, m, ok, c.km, c.m, c.ok)
		}
	}
}

// O caso que abriu o P0. Extrema/MG fica em ~-22.855,-46.318.
func TestResolveCasoDoCard(t *testing.T) {
	at := marcoPos{Lat: -22.0, Lng: -46.3}
	got := ResolveMarcos("Rodovia Fernão Dias km 936", &at)
	if len(got) == 0 {
		t.Fatal("não resolveu BR-381 km 936")
	}
	if got[0].UF != "MG" {
		t.Errorf("UF = %q, quer MG", got[0].UF)
	}
	if d := haversine(got[0].Lat, got[0].Lng, -22.855, -46.318); d > 5000 {
		t.Errorf("caiu a %.0f m de Extrema/MG (esperado < 5 km): %.5f,%.5f", d, got[0].Lat, got[0].Lng)
	}
}

// A quilometragem reinicia por estado: nunca desempatar sozinho, nunca despejar
// 12 estados na lista. Devolve no máximo 2, ordenados por proximidade.
func TestAmbiguidadeDeUF(t *testing.T) {
	semAt := ResolveMarcos("BR-116 km 230", nil)
	comAt := ResolveMarcos("BR-116 km 230", &marcoPos{Lat: -23.5, Lng: -46.6})

	if len(comAt) == 0 {
		t.Fatal("com posição deveria resolver")
	}
	if len(comAt) > maxMarcos {
		t.Errorf("devolveu %d sugestões, teto é %d", len(comAt), maxMarcos)
	}
	// Havendo mais de um estado com esse km, sem posição não dá pra ordenar —
	// e chutar poria o pino em outro estado.
	if len(semAt) > 1 {
		t.Errorf("sem posição não pode devolver múltiplos: %+v", semAt)
	}
	// O primeiro tem que ser o mais próximo de São Paulo.
	if len(comAt) > 1 {
		d0 := haversine(comAt[0].Lat, comAt[0].Lng, -23.5, -46.6)
		d1 := haversine(comAt[1].Lat, comAt[1].Lng, -23.5, -46.6)
		if d0 > d1 {
			t.Errorf("ordem errada: %s (%.0fm) veio antes de %s (%.0fm)",
				comAt[0].UF, d0, comAt[1].UF, d1)
		}
	}
}

func TestSufixoMetrosAndaNaDirecaoDoProximoMarco(t *testing.T) {
	at := marcoPos{Lat: -22.0, Lng: -46.3}
	base := ResolveMarcos("Fernão Dias km 936", &at)
	comSuf := ResolveMarcos("Fernão Dias km 936+700", &at)
	if len(base) == 0 || len(comSuf) == 0 {
		t.Fatal("não resolveu")
	}
	d := haversine(base[0].Lat, base[0].Lng, comSuf[0].Lat, comSuf[0].Lng)
	// 700 m de deslocamento ao longo da via; a corda pode ser menor em curva.
	if d < 300 || d > 900 {
		t.Errorf("+700 deslocou %.0f m, esperado ~700", d)
	}
}

func TestNaoResolveOQueNaoDeve(t *testing.T) {
	at := marcoPos{Lat: -23.5, Lng: -46.6}
	for _, q := range []string{"Avenida Paulista 1000", "km 936", "Anhanguera km 100", ""} {
		if got := ResolveMarcos(q, &at); len(got) != 0 {
			t.Errorf("ResolveMarcos(%q) devolveu %+v, queria vazio", q, got)
		}
	}
}

func TestAssetEmbutidoTemOsMarcosEsperados(t *testing.T) {
	idx := loadMarcos()
	n := 0
	for _, ufs := range idx {
		n += len(ufs)
	}
	// Guard do asset: se o gerador mudar e cortar metade da malha, isto grita.
	if n < 100000 {
		t.Errorf("só %d marcos no asset embutido; esperado > 100 mil", n)
	}
}

func haversine(lat1, lng1, lat2, lng2 float64) float64 {
	const R = 6371000.0
	p1, p2 := lat1*math.Pi/180, lat2*math.Pi/180
	dp := p2 - p1
	dl := (lng2 - lng1) * math.Pi / 180
	h := math.Sin(dp/2)*math.Sin(dp/2) + math.Cos(p1)*math.Cos(p2)*math.Sin(dl/2)*math.Sin(dl/2)
	return 2 * R * math.Asin(math.Sqrt(h))
}
