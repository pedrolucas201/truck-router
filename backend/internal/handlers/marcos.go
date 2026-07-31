package handlers

import (
	_ "embed"
	"encoding/json"
	"math"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
)

// /geocode/marco resolve endereço de rodovia por km ("Fernão Dias km 936") em
// coordenada, a partir dos marcos quilométricos das federais.
//
// POR QUE EXISTE: nenhuma fonte de geocoding entende marco quilométrico. Medido
// em 2026-07-31 contra os 1.939 radares do PNCV (trazem BR + km E coordenada
// oficial), nos MESMOS pontos:
//
//	HERE "BR-x km y, UF" (como o motorista digita)  mediana 158.788 m    0% <=500m
//	HERE + município + bias (mais favorável)        mediana   4.035 m    9%
//	marcos do SNV (isto aqui)                       mediana     400 m   59%
//
// POR QUE NO BACKEND e não como asset no app: geocoding roda ANTES da viagem, com
// rede — as outras fontes já são todas HTTP. Os assets de radar/restrição são
// offline porque são consumidos DIRIGINDO, o que não é o caso aqui. E os 3,5 MB no
// bundle do Flutter triplicaram a suíte de testes (83s -> 259s no mesmo arquivo).
//
// O parse do texto mora aqui, não no app: assim apelido novo de rodovia e dado
// novo do SNV entram sem release.

//go:embed data/marcos_km.csv
var marcosCSV string

// Gerado por tools/marcos_km_gerar.py a partir do SNV_202604A do DNIT.
// Chave "br|km" -> UF -> posição. Indexado sem a UF de propósito: ela é
// justamente o que NÃO vem no texto do motorista.
var (
	marcosOnce sync.Once
	marcosIdx  map[string]map[string]marcoPos
)

type marcoPos struct{ Lat, Lng float64 }

// Nomes populares de rodovias FEDERAIS. Conservador: cada entrada errada manda o
// motorista pra outra rodovia, então só entra nome que designa uma BR sem
// ambiguidade. Estaduais não entram — o SNV não as tem, e mapear "Anhanguera"
// pra uma BR seria inventar.
var apelidos = map[string]string{
	"fernao dias":       "381",
	"regis bittencourt": "116",
	"presidente dutra":  "116",
	"via dutra":         "116",
	"rio santos":        "101",
	"rio bahia":         "116",
	"transamazonica":    "230",
	"belem brasilia":    "153",
}

var (
	kmRe = regexp.MustCompile(`(?i)\bkm\s*(\d+)(?:\s*\+\s*(\d+))?`)
	brRe = regexp.MustCompile(`(?i)\bbr[-\s]?0*(\d{1,3})\b`)
)

// maxMarcos: a quilometragem do SNV REINICIA a cada estado, então "BR-116 km 230"
// existe de verdade em até 12 UFs — e o texto nunca traz o estado. Medido:
// ordenando por proximidade do `at`, a UF certa é a 1ª em 89,6% e a 2ª em 10,4%.
// Devolver as duas e deixar a escolha com o motorista; desempatar sozinho erraria
// 1 caso em 10, jogando o pino a ~87 km de distância.
const maxMarcos = 2

func loadMarcos() map[string]map[string]marcoPos {
	marcosOnce.Do(func() {
		idx := make(map[string]map[string]marcoPos, 90000)
		lines := strings.Split(marcosCSV, "\n")
		for i, l := range lines {
			if i == 0 { // cabeçalho
				continue
			}
			l = strings.TrimSpace(l)
			if l == "" {
				continue
			}
			c := strings.Split(l, ",")
			if len(c) < 5 {
				continue
			}
			lng, err1 := strconv.ParseFloat(c[3], 64)
			lat, err2 := strconv.ParseFloat(c[4], 64)
			if err1 != nil || err2 != nil {
				continue
			}
			k := c[0] + "|" + c[2]
			if idx[k] == nil {
				idx[k] = make(map[string]marcoPos, 2)
			}
			idx[k][c[1]] = marcoPos{Lat: lat, Lng: lng}
		}
		marcosIdx = idx
	})
	return marcosIdx
}

// ParseBr devolve a BR de 3 dígitos citada no texto, por número ou apelido.
func ParseBr(q string) string {
	if m := brRe.FindStringSubmatch(q); m != nil {
		n := m[1]
		for len(n) < 3 {
			n = "0" + n
		}
		return n
	}
	norm := semAcento(strings.ToLower(q))
	for nome, br := range apelidos {
		if strings.Contains(norm, nome) {
			return br
		}
	}
	return ""
}

// ParseKm devolve (km inteiro, metros do sufixo "+700"). ok=false se não há km.
func ParseKm(q string) (km int, metros int, ok bool) {
	m := kmRe.FindStringSubmatch(q)
	if m == nil {
		return 0, 0, false
	}
	km, _ = strconv.Atoi(m[1])
	if m[2] != "" {
		metros, _ = strconv.Atoi(m[2])
	}
	return km, metros, true
}

type marcoItem struct {
	Title string  `json:"title"`
	UF    string  `json:"uf"`
	Lat   float64 `json:"lat"`
	Lng   float64 `json:"lng"`
}

// ResolveMarcos: o miolo, separado do handler pra ser testável sem HTTP.
func ResolveMarcos(q string, at *marcoPos) []marcoItem {
	br := ParseBr(q)
	km, metros, ok := ParseKm(q)
	if br == "" || !ok {
		return nil
	}
	idx := loadMarcos()
	cand := idx[br+"|"+strconv.Itoa(km)]
	if len(cand) == 0 {
		return nil
	}

	ufs := make([]string, 0, len(cand))
	for uf := range cand {
		ufs = append(ufs, uf)
	}
	if len(ufs) > 1 {
		// Sem posição do motorista não há como ordenar, e despejar 12 estados na
		// lista de sugestões é pior que não sugerir.
		if at == nil {
			return nil
		}
		sort.Slice(ufs, func(i, j int) bool {
			return d2(cand[ufs[i]], *at) < d2(cand[ufs[j]], *at)
		})
	} else {
		sort.Strings(ufs) // determinismo
	}

	sufixo := ""
	if metros > 0 {
		sufixo = "+" + strconv.Itoa(metros)
	}
	out := make([]marcoItem, 0, maxMarcos)
	for _, uf := range ufs {
		if len(out) == maxMarcos {
			break
		}
		p := comSufixo(idx, br, uf, km, metros, cand[uf])
		out = append(out, marcoItem{
			Title: "BR-" + br + ", km " + strconv.Itoa(km) + sufixo + " — " + uf,
			UF:    uf, Lat: p.Lat, Lng: p.Lng,
		})
	}
	return out
}

// "+700" = 700 m depois do marco: interpola até o marco seguinte. Sem ele (fim da
// rodovia naquele estado), o próprio marco já é a melhor resposta.
func comSufixo(idx map[string]map[string]marcoPos, br, uf string, km, metros int, base marcoPos) marcoPos {
	if metros == 0 {
		return base
	}
	next, ok := idx[br+"|"+strconv.Itoa(km+1)][uf]
	if !ok {
		return base
	}
	t := math.Min(float64(metros)/1000, 1)
	return marcoPos{
		Lat: base.Lat + (next.Lat-base.Lat)*t,
		Lng: base.Lng + (next.Lng-base.Lng)*t,
	}
}

// GeocodeMarco: GET /geocode/marco?q=<texto>&at=<lat>,<lng>
func GeocodeMarco(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	var at *marcoPos
	if s := r.URL.Query().Get("at"); s != "" {
		if p := strings.SplitN(s, ",", 2); len(p) == 2 {
			lat, e1 := strconv.ParseFloat(strings.TrimSpace(p[0]), 64)
			lng, e2 := strconv.ParseFloat(strings.TrimSpace(p[1]), 64)
			if e1 == nil && e2 == nil {
				at = &marcoPos{Lat: lat, Lng: lng}
			}
		}
	}
	items := ResolveMarcos(q, at)
	if items == nil {
		items = []marcoItem{}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"items": items})
}

// Só ordena candidatos — não é distância de verdade, não usar como métrica.
func d2(a, b marcoPos) float64 {
	dx, dy := a.Lng-b.Lng, a.Lat-b.Lat
	return dx*dx + dy*dy
}

func semAcento(s string) string {
	rep := strings.NewReplacer(
		"á", "a", "à", "a", "â", "a", "ã", "a", "ä", "a",
		"é", "e", "è", "e", "ê", "e", "ë", "e",
		"í", "i", "ì", "i", "î", "i", "ï", "i",
		"ó", "o", "ò", "o", "ô", "o", "õ", "o", "ö", "o",
		"ú", "u", "ù", "u", "û", "u", "ü", "u", "ç", "c",
	)
	return rep.Replace(s)
}
